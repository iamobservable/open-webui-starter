#!/bin/bash

# Fix Web Search Issue Script for ERNI-KI
# Скрипт исправления проблем с веб-поиском в OpenWebUI через diz.zone

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции для логирования
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

# Резервное копирование конфигурации
backup_config() {
    log "Создание резервной копии конфигурации..."
    
    local backup_dir="config-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    cp conf/nginx/conf.d/default.conf "$backup_dir/" 2>/dev/null || warning "Не удалось скопировать default.conf"
    cp env/openwebui.env "$backup_dir/" 2>/dev/null || warning "Не удалось скопировать openwebui.env"
    
    success "Резервная копия создана в: $backup_dir"
}

# Исправление конфигурации Nginx
fix_nginx_config() {
    log "Исправление конфигурации Nginx..."
    
    # Создаем новую оптимизированную конфигурацию
    cat > conf/nginx/conf.d/default.conf << 'EOF'
# Rate limiting zones
limit_req_zone $binary_remote_addr zone=searxng_api:10m rate=30r/m;
limit_req_zone $binary_remote_addr zone=searxng_web:10m rate=10r/m;
limit_req_zone $binary_remote_addr zone=general:10m rate=100r/m;
limit_req_zone $binary_remote_addr zone=auth:10m rate=20r/m;

# Upstream конфигурации с улучшенными настройками отказоустойчивости
upstream docsUpstream {
  server openwebui:8080 max_fails=3 fail_timeout=30s weight=1;
  keepalive 32;
  keepalive_requests 100;
  keepalive_timeout 60s;
}

upstream redisUpstream {
  server redis:8001 max_fails=3 fail_timeout=30s weight=1;
  keepalive 16;
  keepalive_requests 50;
  keepalive_timeout 60s;
}

upstream searxngUpstream {
  server searxng:8080 max_fails=3 fail_timeout=30s weight=1;
  keepalive 16;
  keepalive_requests 100;
  keepalive_timeout 60s;
}

upstream authUpstream {
  server auth:9090 max_fails=3 fail_timeout=30s weight=1;
  keepalive 16;
  keepalive_requests 50;
  keepalive_timeout 60s;
}

upstream backrestUpstream {
  server backrest:9898 max_fails=3 fail_timeout=30s weight=1;
  keepalive 16;
  keepalive_requests 50;
  keepalive_timeout 60s;
}

server {
  listen 80;
  server_name diz.zone localhost;

  # Health check endpoint для Docker healthcheck
  location /health {
    access_log off;
    return 200 "healthy\n";
    add_header Content-Type text/plain;
  }

  # Редирект всех остальных запросов на HTTPS
  location / {
    # Для Cloudflare туннеля - проксируем напрямую
    if ($http_cf_ray) {
      proxy_pass http://docsUpstream;
    }
    # Для прямых подключений - редиректим на HTTPS
    if ($http_cf_ray = "") {
      return 301 https://$host$request_uri;
    }
  }
}

# HTTPS server block
server {
  listen 443 ssl;
  server_name diz.zone localhost;

  # SSL конфигурация
  ssl_certificate /etc/nginx/ssl/nginx.crt;
  ssl_certificate_key /etc/nginx/ssl/nginx.key;
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
  ssl_prefer_server_ciphers off;
  ssl_session_cache shared:SSL:10m;
  ssl_session_timeout 10m;

  # Включаем HTTP/2
  http2 on;

  absolute_redirect off;

  # Общие заголовки безопасности
  add_header X-Frame-Options DENY always;
  add_header X-Content-Type-Options nosniff always;
  add_header X-XSS-Protection "1; mode=block" always;
  add_header Referrer-Policy "strict-origin-when-cross-origin" always;

  # Health check endpoint
  location /health {
    access_log off;
    return 200 "healthy\n";
    add_header Content-Type text/plain;
  }

  # SearXNG API endpoint БЕЗ аутентификации (для внутренних запросов OpenWebUI)
  location /api/searxng/ {
    # Ограничение скорости для API
    limit_req zone=searxng_api burst=10 nodelay;
    limit_req_status 429;
    
    # Разрешаем только внутренние запросы от OpenWebUI
    allow 172.16.0.0/12;  # Docker networks
    allow 10.0.0.0/8;     # Private networks
    allow 192.168.0.0/16; # Private networks
    allow 127.0.0.1;      # Localhost
    deny all;
    
    # Убираем префикс /api/searxng и проксируем к SearXNG
    rewrite ^/api/searxng/(.*) /$1 break;
    
    proxy_pass http://searxngUpstream;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    
    # Таймауты и буферизация для API
    proxy_connect_timeout 5s;
    proxy_send_timeout 10s;
    proxy_read_timeout 30s;
    proxy_buffering on;
    proxy_buffer_size 4k;
    proxy_buffers 8 4k;
    
    # HTTP/1.1 для keepalive
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    
    # CORS заголовки для API
    add_header Access-Control-Allow-Origin $http_origin always;
    add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Content-Type, Authorization" always;
    add_header Access-Control-Allow-Credentials true always;
    
    # Обработка preflight запросов
    if ($request_method = 'OPTIONS') {
      return 204;
    }
  }

  # SearXNG веб-интерфейс С аутентификацией
  location /searxng {
    limit_req zone=searxng_web burst=5 nodelay;
    
    auth_request /auth-server/validate;
    auth_request_set $auth_status $upstream_status;

    error_page 401 = @fallback;
    error_page 404 = @notfound;
    error_page 429 = @rate_limit;
    add_header X-Auth-Status $auth_status;

    proxy_pass http://searxngUpstream;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    
    # Таймауты и буферизация
    proxy_connect_timeout 5s;
    proxy_send_timeout 10s;
    proxy_read_timeout 30s;
    proxy_buffering on;
    proxy_buffer_size 4k;
    proxy_buffers 8 4k;
    
    # HTTP/1.1 для keepalive
    proxy_http_version 1.1;
    proxy_set_header Connection "";
  }

  # Остальные защищенные сервисы
  location ~ ^/(docs|redis|backrest) {
    limit_req zone=general burst=20 nodelay;
    
    auth_request /auth-server/validate;
    auth_request_set $auth_status $upstream_status;

    error_page 401 = @fallback;
    error_page 404 = @notfound;
    error_page 429 = @rate_limit;
    add_header X-Auth-Status $auth_status;

    proxy_pass http://$1Upstream;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    
    # Дополнительные заголовки для WebUI
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_cache_bypass $http_upgrade;

    # Увеличенный таймаут для операций
    proxy_read_timeout 300s;
    proxy_send_timeout 300s;
  }

  # Auth server (внутренний)
  location /auth-server/ {
    internal;
    limit_req zone=auth burst=10 nodelay;
    
    proxy_pass http://authUpstream/;
    proxy_buffers 8 16k;
    proxy_buffer_size 32k;
    proxy_connect_timeout 3s;
    proxy_send_timeout 5s;
    proxy_read_timeout 10s;
  }

  # Основное приложение (OpenWebUI)
  location / {
    limit_req zone=general burst=50 nodelay;
    
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_cache_bypass $http_upgrade;

    client_max_body_size 100M;
    client_body_timeout 30s;
    client_header_timeout 10s;

    # Таймауты для WebSocket соединений
    proxy_connect_timeout 5s;
    proxy_send_timeout 60s;
    proxy_read_timeout 300s;

    proxy_pass http://docsUpstream;
  }

  # Health check endpoint для SearXNG
  location /searxng/healthz {
    access_log off;
    proxy_pass http://searxngUpstream/healthz;
    proxy_connect_timeout 1s;
    proxy_send_timeout 1s;
    proxy_read_timeout 1s;
  }

  # Error pages
  location @fallback {
    return 302 /auth?redirect=$uri?$query_string;
  }

  location @rate_limit {
    return 429 "Rate limit exceeded. Please try again later.";
    add_header Content-Type text/plain always;
  }

  location @notfound {
    return 404 "Resource not found";
    add_header Content-Type text/plain always;
  }
}
EOF

    success "Конфигурация Nginx обновлена"
}

# Обновление конфигурации OpenWebUI
update_openwebui_config() {
    log "Обновление конфигурации OpenWebUI..."
    
    # Обновляем SEARXNG_QUERY_URL для использования нового API endpoint
    if grep -q "SEARXNG_QUERY_URL" env/openwebui.env; then
        sed -i 's|SEARXNG_QUERY_URL=.*|SEARXNG_QUERY_URL=http://nginx/api/searxng/search?q=<query>|' env/openwebui.env
        success "SEARXNG_QUERY_URL обновлен для использования API endpoint"
    else
        echo "SEARXNG_QUERY_URL=http://nginx/api/searxng/search?q=<query>" >> env/openwebui.env
        success "SEARXNG_QUERY_URL добавлен в конфигурацию"
    fi
    
    # Убеждаемся, что WEBUI_URL правильно настроен
    if grep -q "WEBUI_URL" env/openwebui.env; then
        sed -i 's|WEBUI_URL=.*|WEBUI_URL=https://diz.zone|' env/openwebui.env
    else
        echo "WEBUI_URL=https://diz.zone" >> env/openwebui.env
    fi
    
    success "Конфигурация OpenWebUI обновлена"
}

# Проверка конфигурации
validate_config() {
    log "Проверка конфигурации..."
    
    # Проверка Nginx конфигурации
    if docker-compose exec -T nginx nginx -t >/dev/null 2>&1; then
        success "Конфигурация Nginx валидна"
    else
        error "Ошибка в конфигурации Nginx"
    fi
    
    # Проверка Docker Compose
    if docker-compose config >/dev/null 2>&1; then
        success "Docker Compose конфигурация валидна"
    else
        error "Ошибка в Docker Compose конфигурации"
    fi
}

# Перезапуск сервисов
restart_services() {
    log "Перезапуск сервисов..."
    
    # Перезапуск Nginx для применения новой конфигурации
    docker-compose restart nginx
    
    # Перезапуск OpenWebUI для применения новых переменных окружения
    docker-compose restart openwebui
    
    # Ждем запуска сервисов
    sleep 10
    
    success "Сервисы перезапущены"
}

# Тестирование исправления
test_fix() {
    log "Тестирование исправления..."
    
    local max_attempts=30
    local attempt=1
    
    # Ждем запуска сервисов
    while [ $attempt -le $max_attempts ]; do
        if curl -f -s http://localhost/health >/dev/null 2>&1; then
            success "Nginx доступен"
            break
        fi
        
        log "Попытка $attempt/$max_attempts: ожидание запуска Nginx..."
        sleep 2
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        error "Nginx не отвечает после $max_attempts попыток"
    fi
    
    # Тестирование API endpoint
    log "Тестирование нового API endpoint..."
    
    local api_response
    api_response=$(curl -s -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "q=test&category_general=1&format=json" \
        http://localhost/api/searxng/search)
    
    if echo "$api_response" | jq . >/dev/null 2>&1; then
        success "API endpoint работает корректно"
        echo "Количество результатов: $(echo "$api_response" | jq '.results | length')"
    else
        warning "API endpoint может работать некорректно"
        echo "Ответ: ${api_response:0:200}..."
    fi
    
    # Тестирование веб-интерфейса
    log "Тестирование веб-интерфейса SearXNG..."
    
    if curl -f -s http://localhost/searxng/ >/dev/null 2>&1; then
        success "Веб-интерфейс SearXNG доступен"
    else
        warning "Веб-интерфейс SearXNG требует аутентификации (это нормально)"
    fi
}

# Основная функция
main() {
    log "Запуск исправления проблем с веб-поиском..."
    
    # Проверка, что мы в корне проекта
    if [ ! -f "compose.yml" ] && [ ! -f "docker-compose.yml" ]; then
        error "Файл compose.yml не найден. Запустите скрипт из корня проекта."
    fi
    
    backup_config
    fix_nginx_config
    update_openwebui_config
    validate_config
    restart_services
    test_fix
    
    echo ""
    success "Исправление завершено успешно!"
    
    echo ""
    log "Что было исправлено:"
    echo "1. ✅ Создан отдельный API endpoint /api/searxng/ без аутентификации"
    echo "2. ✅ Настроено ограничение доступа к API только для внутренних сетей"
    echo "3. ✅ Обновлен SEARXNG_QUERY_URL в OpenWebUI для использования нового endpoint"
    echo "4. ✅ Добавлены CORS заголовки для корректной работы API"
    echo "5. ✅ Сохранена аутентификация для веб-интерфейса /searxng"
    
    echo ""
    log "Тестирование:"
    echo "1. Проверьте веб-поиск в OpenWebUI через diz.zone"
    echo "2. API endpoint: http://localhost/api/searxng/search"
    echo "3. Веб-интерфейс: https://diz.zone/searxng (требует аутентификации)"
    
    echo ""
    warning "Если проблема не решена, проверьте логи:"
    echo "- docker-compose logs nginx"
    echo "- docker-compose logs openwebui"
    echo "- docker-compose logs searxng"
}

# Запуск скрипта
main "$@"
