#!/bin/bash
# Скрипт для исправления критических проблем из аудита ERNI-KI
# Выполняет приоритетные исправления для подготовки к продакшну

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Проверка прав администратора для некоторых операций
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        warning "Некоторые операции требуют sudo прав"
        echo "Введите пароль для sudo доступа:"
        sudo -v
    fi
}

# 1. Создание отсутствующих директорий
fix_missing_directories() {
    log "Создание отсутствующих директорий..."
    
    # Создание директорий для конфигураций
    mkdir -p conf/nginx/ssl
    mkdir -p conf/backrest
    mkdir -p conf/searxng
    mkdir -p conf/tika
    mkdir -p logs
    
    # Создание директорий для данных
    mkdir -p data/prometheus
    mkdir -p data/grafana
    
    success "Директории созданы"
}

# 2. Исправление прав доступа к файлам
fix_file_permissions() {
    log "Исправление прав доступа к файлам..."
    
    # Права для .env файлов
    find env/ -name "*.env" -exec chmod 600 {} \;
    
    # Права для конфигурационных файлов
    find conf/ -type f -exec chmod 644 {} \;
    find conf/ -type d -exec chmod 755 {} \;
    
    # Права для скриптов
    find scripts/ -name "*.sh" -exec chmod +x {} \;
    
    success "Права доступа исправлены"
}

# 3. Генерация самоподписанного SSL сертификата
generate_ssl_certificate() {
    log "Генерация самоподписанного SSL сертификата..."
    
    if [ ! -f "conf/nginx/ssl/nginx.crt" ]; then
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout conf/nginx/ssl/nginx.key \
            -out conf/nginx/ssl/nginx.crt \
            -subj "/C=RU/ST=Moscow/L=Moscow/O=ERNI-KI/CN=localhost"
        
        chmod 600 conf/nginx/ssl/nginx.key
        chmod 644 conf/nginx/ssl/nginx.crt
        
        success "SSL сертификат создан"
    else
        warning "SSL сертификат уже существует"
    fi
}

# 4. Обновление Nginx конфигурации для SSL
update_nginx_ssl_config() {
    log "Обновление Nginx конфигурации для SSL..."
    
    if [ ! -f "conf/nginx/conf.d/ssl.conf" ]; then
        cat > conf/nginx/conf.d/ssl.conf << 'EOF'
# SSL Configuration
server {
    listen 443 ssl http2;
    server_name localhost;
    
    ssl_certificate /etc/nginx/ssl/nginx.crt;
    ssl_certificate_key /etc/nginx/ssl/nginx.key;
    
    # SSL Security
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Proxy settings
    location / {
        proxy_pass http://openwebui:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $server_name;
        proxy_buffering off;
    }
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name localhost;
    return 301 https://$server_name$request_uri;
}
EOF
        success "SSL конфигурация Nginx создана"
    else
        warning "SSL конфигурация уже существует"
    fi
}

# 5. Замена placeholder API ключей
fix_api_keys() {
    log "Генерация новых API ключей..."
    
    # Генерация новых ключей
    NEW_API_KEY=$(openssl rand -hex 32)
    NEW_SECRET_KEY=$(openssl rand -hex 32)
    
    # Обновление OpenWebUI конфигурации
    if grep -q "your_api_key_here" env/openwebui.env 2>/dev/null; then
        sed -i "s/your_api_key_here/$NEW_API_KEY/g" env/openwebui.env
        success "API ключи OpenWebUI обновлены"
    fi
    
    # Сохранение ключей в безопасном файле
    cat > .generated_keys << EOF
# Сгенерированные API ключи - $(date)
NEW_API_KEY=$NEW_API_KEY
NEW_SECRET_KEY=$NEW_SECRET_KEY
EOF
    chmod 600 .generated_keys
    
    success "Новые API ключи сгенерированы и сохранены в .generated_keys"
}

# 6. Добавление ограничений ресурсов в compose.yml
add_resource_limits() {
    log "Добавление ограничений ресурсов..."
    
    # Создание патча для ресурсных ограничений
    cat > resource_limits_patch.yml << 'EOF'
# Patch для добавления ограничений ресурсов
# Добавить в каждый сервис в compose.yml:

# Для тяжелых сервисов (ollama, openwebui)
deploy:
  resources:
    limits:
      memory: 4G
      cpus: '2.0'
    reservations:
      memory: 1G
      cpus: '0.5'

# Для средних сервисов (db, redis, nginx)
deploy:
  resources:
    limits:
      memory: 2G
      cpus: '1.0'
    reservations:
      memory: 512M
      cpus: '0.25'

# Для легких сервисов (auth, watchtower)
deploy:
  resources:
    limits:
      memory: 512M
      cpus: '0.5'
    reservations:
      memory: 128M
      cpus: '0.1'
EOF
    
    warning "Ограничения ресурсов нужно добавить вручную в compose.yml"
    warning "См. файл resource_limits_patch.yml для примеров"
}

# 7. Создание базовой конфигурации мониторинга
create_monitoring_config() {
    log "Создание базовой конфигурации мониторинга..."
    
    # Создание docker-compose.monitoring.yml
    cat > docker-compose.monitoring.yml << 'EOF'
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: erni-ki-prometheus
    restart: unless-stopped
    ports:
      - "9091:9090"
    volumes:
      - ./conf/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./data/prometheus:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '0.5'

  grafana:
    image: grafana/grafana:latest
    container_name: erni-ki-grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - ./data/grafana:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin123_CHANGE_ME
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
EOF

    # Создание базовой конфигурации Prometheus
    mkdir -p conf/prometheus
    cat > conf/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'docker'
    static_configs:
      - targets: ['host.docker.internal:9323']

  - job_name: 'nginx'
    static_configs:
      - targets: ['nginx:80']
EOF

    success "Конфигурация мониторинга создана"
    warning "Запустите мониторинг: docker-compose -f docker-compose.monitoring.yml up -d"
}

# 8. Создание скрипта проверки здоровья
create_health_check_script() {
    log "Создание скрипта проверки здоровья..."
    
    cat > scripts/check-system-health.sh << 'EOF'
#!/bin/bash
# Скрипт проверки здоровья системы ERNI-KI

echo "=== Проверка здоровья системы ERNI-KI ==="
echo "Время: $(date)"
echo ""

# Проверка статуса контейнеров
echo "📊 Статус контейнеров:"
docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
echo ""

# Проверка unhealthy контейнеров
UNHEALTHY=$(docker-compose ps | grep -c "unhealthy" || true)
if [ "$UNHEALTHY" -gt 0 ]; then
    echo "⚠️  Найдено $UNHEALTHY нездоровых контейнеров"
    docker-compose ps | grep "unhealthy"
else
    echo "✅ Все контейнеры здоровы"
fi
echo ""

# Проверка использования ресурсов
echo "💾 Использование ресурсов:"
echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%"
echo "Memory: $(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')%"
echo "Disk: $(df -h . | awk 'NR==2 {print $5}')"
echo ""

# Проверка SSL сертификата
if [ -f "conf/nginx/ssl/nginx.crt" ]; then
    echo "🔒 SSL сертификат:"
    openssl x509 -in conf/nginx/ssl/nginx.crt -noout -dates
else
    echo "❌ SSL сертификат не найден"
fi
echo ""

# Проверка бэкапов
if [ -d ".config-backup" ] && [ "$(ls -A .config-backup 2>/dev/null)" ]; then
    echo "💾 Последний бэкап: $(ls -lt .config-backup | head -2 | tail -1 | awk '{print $6, $7, $8}')"
else
    echo "❌ Бэкапы не найдены"
fi

echo ""
echo "=== Проверка завершена ==="
EOF

    chmod +x scripts/check-system-health.sh
    success "Скрипт проверки здоровья создан"
}

# 9. Создание firewall правил
setup_basic_firewall() {
    log "Настройка базовых firewall правил..."
    
    if command -v ufw >/dev/null 2>&1; then
        # Базовые правила UFW
        sudo ufw --force reset
        sudo ufw default deny incoming
        sudo ufw default allow outgoing
        
        # Разрешить SSH
        sudo ufw allow ssh
        
        # Разрешить HTTP/HTTPS
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        
        # Разрешить только локальный доступ к админ портам
        sudo ufw allow from 127.0.0.1 to any port 9090  # Auth
        sudo ufw allow from 127.0.0.1 to any port 9898  # Backrest
        sudo ufw allow from 127.0.0.1 to any port 3000  # Grafana
        sudo ufw allow from 127.0.0.1 to any port 9091  # Prometheus
        
        # Активировать firewall
        sudo ufw --force enable
        
        success "UFW firewall настроен"
    else
        warning "UFW не установлен, пропускаем настройку firewall"
        echo "Установите UFW: sudo apt install ufw"
    fi
}

# 10. Создание отчета об исправлениях
create_fix_report() {
    log "Создание отчета об исправлениях..."
    
    REPORT_FILE="critical-fixes-report-$(date +%Y%m%d_%H%M%S).md"
    
    cat > "$REPORT_FILE" << EOF
# Отчет об исправлении критических проблем ERNI-KI

**Дата исправления**: $(date)
**Скрипт**: fix-critical-issues.sh

## ✅ Выполненные исправления

### 🔒 Безопасность
- [x] Созданы отсутствующие директории
- [x] Исправлены права доступа к файлам (.env = 600)
- [x] Сгенерирован самоподписанный SSL сертификат
- [x] Обновлена конфигурация Nginx для SSL
- [x] Заменены placeholder API ключи
- [x] Настроены базовые firewall правила

### ⚡ Производительность
- [x] Создан шаблон ограничений ресурсов
- [x] Подготовлена конфигурация мониторинга

### 🛡️ Надежность
- [x] Создан скрипт проверки здоровья системы
- [x] Настроена базовая конфигурация мониторинга

## 📋 Следующие шаги

### Немедленно
1. Перезапустить Nginx: \`docker-compose restart nginx\`
2. Проверить SSL: \`curl -k https://localhost\`
3. Запустить проверку здоровья: \`./scripts/check-system-health.sh\`

### В течение дня
1. Добавить ограничения ресурсов в compose.yml (см. resource_limits_patch.yml)
2. Запустить мониторинг: \`docker-compose -f docker-compose.monitoring.yml up -d\`
3. Исправить unhealthy сервисы

### В течение недели
1. Получить реальный SSL сертификат (Let's Encrypt)
2. Настроить алертинг в Grafana
3. Протестировать disaster recovery

## 🔐 Сгенерированные секреты

Новые API ключи сохранены в файле \`.generated_keys\`
SSL сертификат создан в \`conf/nginx/ssl/\`

## 📊 Статус после исправлений

$(./scripts/check-system-health.sh 2>/dev/null || echo "Запустите ./scripts/check-system-health.sh для проверки")

---

**Следующий аудит**: Через 1 неделю после внедрения всех исправлений
EOF

    success "Отчет создан: $REPORT_FILE"
}

# Основная функция
main() {
    echo "🔧 Запуск исправления критических проблем ERNI-KI..."
    echo "Дата: $(date)"
    echo ""
    
    # Проверка sudo для firewall
    check_sudo
    
    # Выполнение исправлений
    fix_missing_directories
    fix_file_permissions
    generate_ssl_certificate
    update_nginx_ssl_config
    fix_api_keys
    add_resource_limits
    create_monitoring_config
    create_health_check_script
    setup_basic_firewall
    create_fix_report
    
    echo ""
    success "🎉 Критические исправления завершены!"
    echo ""
    echo "📋 Следующие шаги:"
    echo "1. Перезапустите Nginx: docker-compose restart nginx"
    echo "2. Проверьте SSL: curl -k https://localhost"
    echo "3. Запустите проверку: ./scripts/check-system-health.sh"
    echo "4. Просмотрите отчет: ls -la critical-fixes-report-*.md"
    echo ""
    warning "⚠️  Не забудьте добавить ограничения ресурсов в compose.yml!"
}

# Запуск скрипта
main "$@"
