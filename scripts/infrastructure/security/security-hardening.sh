#!/bin/bash
# Скрипт усиления безопасности для проекта ERNI-KI
# Автоматическое исправление критических проблем безопасности

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции логирования
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Проверка зависимостей
check_dependencies() {
    log "Проверка зависимостей..."

    local deps=("openssl" "docker" "docker-compose")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error "Зависимость не найдена: $dep"
        fi
    done

    success "Все зависимости установлены"
}

# Генерация секретных ключей
generate_secrets() {
    log "Генерация секретных ключей..."

    # Генерация основных секретов
    JWT_SECRET=$(openssl rand -hex 32)
    WEBUI_SECRET_KEY=$(openssl rand -hex 32)
    SEARXNG_SECRET=$(openssl rand -hex 32)
    POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

    success "Секретные ключи сгенерированы"
}

# Обновление переменных окружения
update_env_files() {
    log "Обновление файлов переменных окружения..."

    # Обновление auth.env
    if [ -f "env/auth.env" ]; then
        sed -i "s/JWT_SECRET=.*/JWT_SECRET=${JWT_SECRET}/" env/auth.env
        sed -i "s/GIN_MODE=.*/GIN_MODE=release/" env/auth.env
        success "Обновлен env/auth.env"
    else
        warning "Файл env/auth.env не найден"
    fi

    # Обновление openwebui.env
    if [ -f "env/openwebui.env" ]; then
        sed -i "s/WEBUI_SECRET_KEY=.*/WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}/" env/openwebui.env
        sed -i "s/ANONYMIZED_TELEMETRY=.*/ANONYMIZED_TELEMETRY=false/" env/openwebui.env
        sed -i "s/ENV=.*/ENV=production/" env/openwebui.env
        success "Обновлен env/openwebui.env"
    else
        warning "Файл env/openwebui.env не найден"
    fi

    # Обновление searxng.env
    if [ -f "env/searxng.env" ]; then
        sed -i "s/SEARXNG_SECRET=.*/SEARXNG_SECRET=${SEARXNG_SECRET}/" env/searxng.env
        success "Обновлен env/searxng.env"
    else
        warning "Файл env/searxng.env не найден"
    fi

    # Обновление db.env
    if [ -f "env/db.env" ]; then
        sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${POSTGRES_PASSWORD}/" env/db.env
        success "Обновлен env/db.env"
    else
        warning "Файл env/db.env не найден"
    fi

    # Обновление redis.env
    if [ -f "env/redis.env" ]; then
        if grep -q "REDIS_ARGS" env/redis.env; then
            sed -i "s/# REDIS_ARGS=.*/REDIS_ARGS=\"--requirepass ${REDIS_PASSWORD}\"/" env/redis.env
        else
            echo "REDIS_ARGS=\"--requirepass ${REDIS_PASSWORD}\"" >> env/redis.env
        fi
        success "Обновлен env/redis.env"
    else
        warning "Файл env/redis.env не найден"
    fi
}

# Создание безопасной конфигурации Nginx
create_secure_nginx_config() {
    log "Создание безопасной конфигурации Nginx..."

    local nginx_conf="conf/nginx/nginx.conf"
    local default_conf="conf/nginx/conf.d/default.conf"

    # Создание основной конфигурации nginx.conf
    cat > "$nginx_conf" << 'EOF'
user nginx;
worker_processes auto;

error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Логирование
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    # Основные настройки
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    # Безопасность
    server_tokens off;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' ws: wss:;" always;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=auth:10m rate=10r/m;
    limit_req_zone $binary_remote_addr zone=api:10m rate=100r/m;
    limit_req_zone $binary_remote_addr zone=general:10m rate=200r/m;

    # Размеры запросов
    client_max_body_size 20M;
    client_body_timeout 10s;
    client_header_timeout 10s;

    # Gzip сжатие
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/javascript
        application/xml+rss
        application/json;

    include /etc/nginx/conf.d/*.conf;
}
EOF

    success "Создана безопасная конфигурация Nginx"
}

# Создание улучшенной конфигурации default.conf
create_secure_default_conf() {
    log "Создание безопасной конфигурации default.conf..."

    local default_conf="conf/nginx/conf.d/default.conf"

    cat > "$default_conf" << 'EOF'
# Upstream серверы с улучшенными настройками
upstream docsUpstream {
    server openwebui:8080 max_fails=3 fail_timeout=30s weight=1;
    keepalive 32;
    keepalive_requests 100;
    keepalive_timeout 60s;
}

upstream redisUpstream {
    server redis:8001 max_fails=3 fail_timeout=30s weight=1;
    keepalive 16;
}

upstream searxngUpstream {
    server searxng:8080 max_fails=3 fail_timeout=30s weight=1;
    keepalive 16;
}

upstream authUpstream {
    server auth:9090 max_fails=3 fail_timeout=30s weight=1;
    keepalive 16;
}

# Основной сервер
server {
    listen 80;
    server_name localhost;  # Замените на ваш домен

    # Отключение абсолютных редиректов
    absolute_redirect off;

    # Защищенные эндпоинты с аутентификацией
    location ~ ^/(docs|redis|searxng) {
        # Rate limiting
        limit_req zone=api burst=20 nodelay;

        # Аутентификация
        auth_request /auth-server/validate;
        auth_request_set $auth_status $upstream_status;
        auth_request_set $auth_user $upstream_http_x_user;

        # Обработка ошибок
        error_page 401 = @auth_required;
        error_page 403 = @access_denied;
        error_page 404 = @not_found;

        # Заголовки аутентификации
        add_header X-Auth-Status $auth_status;
        add_header X-Auth-User $auth_user;

        # Проксирование
        proxy_pass http://$1Upstream;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-User $auth_user;

        # Таймауты
        proxy_connect_timeout 5s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        # Буферизация
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
    }

    # Внутренний эндпоинт аутентификации
    location /auth-server/ {
        internal;
        proxy_pass http://authUpstream/;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header X-Original-URI $request_uri;
        proxy_set_header X-Original-Remote-Addr $remote_addr;
        proxy_set_header X-Original-Host $host;

        # Таймауты для аутентификации
        proxy_connect_timeout 3s;
        proxy_send_timeout 3s;
        proxy_read_timeout 3s;
    }

    # Основное приложение
    location / {
        # Rate limiting
        limit_req zone=general burst=50 nodelay;

        # WebSocket поддержка
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_cache_bypass $http_upgrade;

        # Стандартные заголовки
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Проксирование
        proxy_pass http://docsUpstream;

        # Таймауты
        proxy_connect_timeout 5s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;

        # Буферизация для больших ответов
        proxy_buffering on;
        proxy_buffer_size 8k;
        proxy_buffers 16 8k;
        proxy_busy_buffers_size 16k;
    }

    # Обработчики ошибок
    location @auth_required {
        return 302 /auth?redirect=$uri$is_args$query_string;
    }

    location @access_denied {
        return 403 "Access Denied";
    }

    location @not_found {
        return 404 "Not Found";
    }

    # Healthcheck эндпоинт
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}

# Переменная для WebSocket соединений
map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}
EOF

    success "Создана улучшенная конфигурация default.conf"
}

# Создание backup скрипта
create_backup_script() {
    log "Создание скрипта резервного копирования..."

    cat > "scripts/backup.sh" << 'EOF'
#!/bin/bash
# Скрипт резервного копирования ERNI-KI

BACKUP_DIR="/backup/erni-ki"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${DATE}"

mkdir -p "$BACKUP_PATH"

# Backup PostgreSQL
docker compose exec -T db pg_dump -U postgres openwebui > "${BACKUP_PATH}/postgres_backup.sql"

# Backup Redis
docker compose exec -T redis redis-cli --rdb - > "${BACKUP_PATH}/redis_backup.rdb"

# Backup конфигураций
tar -czf "${BACKUP_PATH}/configs.tar.gz" env/ conf/

# Backup данных приложений
tar -czf "${BACKUP_PATH}/data.tar.gz" data/

echo "Backup completed: ${BACKUP_PATH}"
EOF

    chmod +x "scripts/backup.sh"
    success "Создан скрипт резервного копирования"
}

# Основная функция
main() {
    log "Запуск скрипта усиления безопасности ERNI-KI..."

    # Проверка, что мы в корне проекта
    if [ ! -f "compose.yml.example" ]; then
        error "Скрипт должен запускаться из корня проекта ERNI-KI"
    fi

    check_dependencies
    generate_secrets
    update_env_files
    create_secure_nginx_config
    create_secure_default_conf
    create_backup_script

    success "Усиление безопасности завершено!"

    echo ""
    log "Следующие шаги:"
    echo "1. Проверьте обновленные файлы переменных окружения"
    echo "2. Настройте Cloudflare туннель с вашим доменом"
    echo "3. Перезапустите сервисы: docker compose down && docker compose up -d"
    echo "4. Настройте регулярные backup'ы"

    warning "ВАЖНО: Сохраните сгенерированные пароли в безопасном месте!"
}

# Запуск скрипта
main "$@"
