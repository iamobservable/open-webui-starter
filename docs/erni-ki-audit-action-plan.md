# 🎯 ERNI-KI: План действий по результатам аудита конфигурации

**Дата создания:** $(date)  
**Статус:** К исполнению  
**Приоритет:** Критический  

## 🚨 НЕМЕДЛЕННЫЕ ДЕЙСТВИЯ (0-24 часа)

### 1. Исправление критических проблем безопасности

#### Команды для выполнения:
```bash
# Переход в директорию проекта
cd /home/konstantin/Documents/augment-projects/erni-ki

# Остановка системы для безопасного обновления
docker compose down
cd monitoring && docker compose -f docker-compose.monitoring.yml down && cd ..

# Генерация безопасных паролей
POSTGRES_PASSWORD=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 32)
BACKREST_PASSWORD=$(openssl rand -base64 32)

# Обновление паролей в env файлах
sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${POSTGRES_PASSWORD}/" env/db.env
echo "REDIS_ARGS=\"--requirepass ${REDIS_PASSWORD} --maxmemory 1gb --maxmemory-policy allkeys-lru\"" > env/redis.env
sed -i "s/BACKREST_PASSWORD=.*/BACKREST_PASSWORD=${BACKREST_PASSWORD}/" env/backrest.env

# Удаление placeholder API ключей
sed -i 's/OPENAI_API_KEY=your_openai_api_key_here/# OPENAI_API_KEY=SET_YOUR_REAL_KEY_HERE/' env/openwebui.env
sed -i 's/AUDIO_TTS_API_KEY=your_api_key_here/# AUDIO_TTS_API_KEY=SET_YOUR_REAL_KEY_HERE/' env/openwebui.env

# Установка правильных прав доступа
chmod 600 env/*.env
chmod 600 conf/nginx/ssl/*.key
chmod 644 conf/nginx/ssl/*.crt

# Создание директории для secrets
mkdir -p secrets
echo "${POSTGRES_PASSWORD}" > secrets/postgres_password.txt
echo "${REDIS_PASSWORD}" > secrets/redis_password.txt
echo "${BACKREST_PASSWORD}" > secrets/backrest_password.txt
chmod 600 secrets/*.txt

echo "✅ Критические проблемы безопасности исправлены!"
```

### 2. Добавление ресурсных ограничений

#### Обновление compose.yml:
```bash
# Создание backup
cp compose.yml compose.yml.backup

# Добавление ресурсных ограничений для LiteLLM
cat >> compose.yml << 'EOF'

  # Ресурсные ограничения для LiteLLM
  litellm:
    deploy:
      resources:
        limits:
          memory: 2G
          cpus: "1.0"
        reservations:
          memory: 1G
          cpus: "0.5"
EOF
```

### 3. Исправление health check команд

#### Обновление monitoring/docker-compose.monitoring.yml:
```bash
cd monitoring

# Backup конфигурации
cp docker-compose.monitoring.yml docker-compose.monitoring.yml.backup

# Исправление health check для Node Exporter
sed -i 's/wget --no-verbose --tries=1 --spider/curl -f/' docker-compose.monitoring.yml

# Исправление health check для cAdvisor
sed -i 's/wget --no-verbose --tries=1 --spider http:\/\/localhost:8080\/healthz/curl -f http:\/\/localhost:8080\/healthz/' docker-compose.monitoring.yml

cd ..
```

## ⚡ СРОЧНЫЕ ДЕЙСТВИЯ (1-3 дня)

### 4. Настройка сетевой изоляции

#### Создание изолированных сетей:
```bash
# Добавление сетевой конфигурации в compose.yml
cat >> compose.yml << 'EOF'

networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
    internal: true
  monitoring:
    driver: bridge
    internal: true
EOF
```

### 5. Добавление security headers в Nginx

#### Обновление conf/nginx/nginx.conf:
```bash
# Backup конфигурации
cp conf/nginx/nginx.conf conf/nginx/nginx.conf.backup

# Добавление security headers
cat >> conf/nginx/nginx.conf << 'EOF'

  # Security headers
  add_header X-Frame-Options DENY always;
  add_header X-Content-Type-Options nosniff always;
  add_header X-XSS-Protection "1; mode=block" always;
  add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
  server_tokens off;

  # Rate limiting
  limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
  limit_req_zone $binary_remote_addr zone=login:10m rate=1r/s;
EOF
```

### 6. Оптимизация PostgreSQL

#### Добавление настроек производительности:
```bash
cat >> env/db.env << 'EOF'

# Оптимизации производительности PostgreSQL
POSTGRES_SHARED_PRELOAD_LIBRARIES=pg_stat_statements,vector
POSTGRES_MAX_CONNECTIONS=200
POSTGRES_SHARED_BUFFERS=256MB
POSTGRES_EFFECTIVE_CACHE_SIZE=1GB
POSTGRES_WORK_MEM=4MB
POSTGRES_MAINTENANCE_WORK_MEM=64MB
EOF
```

## 📅 ПЛАНОВЫЕ ДЕЙСТВИЯ (4-7 дней)

### 7. Настройка мониторинга безопасности

#### Добавление алертов безопасности:
```bash
cd monitoring

# Создание файла с алертами безопасности
cat > security_alerts.yml << 'EOF'
groups:
- name: security
  rules:
  - alert: HighErrorRate
    expr: rate(nginx_http_requests_total{status=~"5.."}[5m]) > 0.1
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "High 5xx error rate detected"
      
  - alert: SuspiciousLoginAttempts
    expr: rate(auth_failed_attempts_total[5m]) > 5
    for: 1m
    labels:
      severity: warning
    annotations:
      summary: "Multiple failed login attempts detected"
      
  - alert: UnauthorizedAPIAccess
    expr: rate(nginx_http_requests_total{status="401"}[5m]) > 10
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High rate of unauthorized API access attempts"
EOF

# Обновление prometheus.yml для включения новых алертов
sed -i '/alert_rules.yml/a\  - "security_alerts.yml"' prometheus.yml

cd ..
```

### 8. Внедрение Docker secrets

#### Обновление compose.yml для использования secrets:
```bash
cat >> compose.yml << 'EOF'

secrets:
  postgres_password:
    file: ./secrets/postgres_password.txt
  redis_password:
    file: ./secrets/redis_password.txt
  backrest_password:
    file: ./secrets/backrest_password.txt
EOF
```

## 🔄 ДОЛГОСРОЧНЫЕ УЛУЧШЕНИЯ (1-4 недели)

### 9. Автоматизация ротации ключей

#### Создание скрипта ротации:
```bash
cat > scripts/rotate-secrets.sh << 'EOF'
#!/bin/bash
# Скрипт ротации секретов ERNI-KI

echo "🔄 Ротация секретов ERNI-KI..."

# Генерация новых паролей
NEW_POSTGRES_PASSWORD=$(openssl rand -base64 32)
NEW_REDIS_PASSWORD=$(openssl rand -base64 32)
NEW_BACKREST_PASSWORD=$(openssl rand -base64 32)

# Обновление secrets
echo "${NEW_POSTGRES_PASSWORD}" > secrets/postgres_password.txt
echo "${NEW_REDIS_PASSWORD}" > secrets/redis_password.txt
echo "${NEW_BACKREST_PASSWORD}" > secrets/backrest_password.txt

# Перезапуск сервисов с новыми секретами
docker compose restart db redis backrest

echo "✅ Ротация секретов завершена!"
EOF

chmod +x scripts/rotate-secrets.sh
```

### 10. Настройка WAF (Web Application Firewall)

#### Активация ModSecurity:
```bash
# Создание базовой конфигурации WAF
cat > conf/nginx/waf.conf << 'EOF'
# ModSecurity конфигурация
load_module modules/ngx_http_modsecurity_module.so;

http {
    modsecurity on;
    modsecurity_rules_file /etc/nginx/modsec/main.conf;
}
EOF
```

## ✅ ПРОВЕРКА ВЫПОЛНЕНИЯ

### Команды для проверки статуса исправлений:

```bash
# 1. Проверка безопасности паролей
echo "🔒 Проверка паролей:"
grep -E "(CHANGE|your_|password)" env/*.env || echo "✅ Нет паролей по умолчанию"

# 2. Проверка прав доступа
echo "🔐 Проверка прав доступа:"
ls -la env/*.env | awk '$1 !~ /^-rw-------/ {print "❌ " $9 " имеет неправильные права"}'
ls -la conf/nginx/ssl/*.key | awk '$1 !~ /^-rw-------/ {print "❌ " $9 " имеет неправильные права"}'

# 3. Проверка ресурсных ограничений
echo "⚡ Проверка ресурсных ограничений:"
grep -A 10 "deploy:" compose.yml | grep -E "(memory|cpus)" || echo "❌ Отсутствуют ресурсные ограничения"

# 4. Проверка health checks
echo "🏥 Проверка health checks:"
grep -c "healthcheck:" compose.yml monitoring/docker-compose.monitoring.yml

# 5. Проверка security headers
echo "🛡️ Проверка security headers:"
grep -E "(X-Frame-Options|X-Content-Type-Options)" conf/nginx/nginx.conf || echo "❌ Отсутствуют security headers"

# 6. Запуск системы и проверка статуса
echo "🚀 Запуск системы:"
docker compose up -d
cd monitoring && docker compose -f docker-compose.monitoring.yml up -d && cd ..

# Ожидание запуска
sleep 30

# Проверка статуса сервисов
echo "📊 Статус сервисов:"
docker compose ps
cd monitoring && docker compose -f docker-compose.monitoring.yml ps && cd ..
```

## 📊 МЕТРИКИ УСПЕХА

После выполнения всех действий должны быть достигнуты следующие показатели:

- [ ] **Безопасность**: 0 паролей по умолчанию, все env файлы с правами 600
- [ ] **Производительность**: Все сервисы с ресурсными ограничениями
- [ ] **Мониторинг**: 100% health checks работают корректно
- [ ] **Сеть**: Изолированные сети для разных типов сервисов
- [ ] **Алерты**: Настроены алерты безопасности и производительности

## 🔄 РЕГУЛЯРНОЕ ОБСЛУЖИВАНИЕ

### Еженедельные задачи:
```bash
# Проверка логов безопасности
scripts/security-monitor.sh

# Ротация логов
docker compose exec nginx logrotate /etc/logrotate.conf

# Проверка обновлений
scripts/check-updates.sh
```

### Ежемесячные задачи:
```bash
# Ротация секретов
scripts/rotate-secrets.sh

# Полный аудит конфигурации
scripts/comprehensive-audit.sh

# Резервное копирование конфигураций
scripts/backup-configs.sh
```

---

**Ответственный за выполнение:** Системный администратор  
**Срок выполнения критических задач:** 24 часа  
**Контроль выполнения:** Ежедневные проверки статуса  
**Отчетность:** Еженедельные отчеты о прогрессе
