# 🌐 Nginx Configuration Guide - ERNI-KI

> **Версия:** 9.0 | **Дата:** 2025-09-11 | **Статус:** Production Ready

## 📋 Обзор

Nginx в ERNI-KI выполняет роль reverse proxy с поддержкой SSL/TLS, WebSocket,
rate limiting и кэширования. После оптимизации v9.0 конфигурация стала модульной
и maintainable.

## 🏗️ Архитектура конфигурации

### 📁 Структура файлов

```bash
conf/nginx/
├── nginx.conf                    # Основная конфигурация
│   ├── Map директивы             # Условная логика
│   ├── Upstream блоки            # Backend серверы
│   ├── Rate limiting zones       # Защита от DDoS
│   └── Proxy cache настройки     # Кэширование
├── conf.d/default.conf          # Server блоки
│   ├── Server :80               # HTTP → HTTPS redirect
│   ├── Server :443              # HTTPS с полной функциональностью
│   └── Server :8080             # Cloudflare туннель
└── includes/                     # Переиспользуемые модули
    ├── openwebui-common.conf     # OpenWebUI proxy настройки
    ├── searxng-api-common.conf   # SearXNG API конфигурация
    ├── searxng-web-common.conf   # SearXNG веб-интерфейс
    └── websocket-common.conf     # WebSocket proxy
```

## 🔧 Ключевые компоненты

### 1. Map директивы (nginx.conf)

```nginx
# Определение Cloudflare туннеля
map $server_port $is_cloudflare_tunnel {
  default 0;
  8080 1;
}

# Условный X-Request-ID заголовок
map $is_cloudflare_tunnel $request_id_header {
  default "";
  1 $final_request_id;
}

# Универсальная переменная для include файлов
map $is_cloudflare_tunnel $universal_request_id {
  default $final_request_id;
  1 $final_request_id;
}
```

### 2. Upstream блоки

```nginx
# OpenWebUI backend
upstream openwebui_backend {
  server openwebui:8080 max_fails=3 fail_timeout=30s weight=1;
  keepalive 64;
  keepalive_requests 1000;
  keepalive_timeout 60s;
}

# SearXNG upstream для RAG поиска
upstream searxngUpstream {
  server searxng:8080 max_fails=3 fail_timeout=30s weight=1;
  keepalive 48;
  keepalive_requests 200;
  keepalive_timeout 60s;
}
```

### 3. Rate Limiting

```nginx
# Зоны ограничения скорости
limit_req_zone $binary_remote_addr zone=general:20m rate=50r/s;
limit_req_zone $binary_remote_addr zone=api:20m rate=30r/s;
limit_req_zone $binary_remote_addr zone=searxng_api:10m rate=60r/s;
limit_req_zone $binary_remote_addr zone=websocket:10m rate=20r/s;

# Connection limiting
limit_conn_zone $binary_remote_addr zone=perip:10m;
limit_conn_zone $server_name zone=perserver:10m;
```

## 🚪 Server блоки

### Port 80 - HTTP Redirect

```nginx
server {
  listen 80;
  server_name ki.erni-gruppe.ch diz.zone localhost;

  # Принудительное перенаправление на HTTPS
  return 301 https://$host$request_uri;
}
```

### Port 443 - HTTPS Production

```nginx
server {
  listen 443 ssl;
  http2 on;
  server_name ki.erni-gruppe.ch diz.zone localhost;

  # SSL конфигурация
  ssl_certificate /etc/nginx/ssl/nginx-fullchain.crt;
  ssl_certificate_key /etc/nginx/ssl/nginx.key;
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_verify_client off;  # Исправление для localhost

  # Security headers (оптимизированные для localhost)
  add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' localhost:*; ...";
  add_header Access-Control-Allow-Origin "https://ki.erni-gruppe.ch https://localhost ...";
}
```

### Port 8080 - Cloudflare Tunnel

```nginx
server {
  listen 8080;
  server_name ki.erni-gruppe.ch diz.zone localhost;

  # Оптимизированный для внешнего доступа
  # Без HTTPS редиректов
  # Использует $request_id_header для логирования
}
```

## 📦 Include файлы

### openwebui-common.conf

```nginx
# Общие настройки для OpenWebUI proxy
limit_req zone=general burst=20 nodelay;
limit_conn perip 30;
limit_conn perserver 2000;

# Стандартные proxy заголовки
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Request-ID $universal_request_id;

# HTTP версия и соединения
proxy_http_version 1.1;
proxy_set_header Connection "";

# Таймауты
proxy_connect_timeout 30s;
proxy_send_timeout 60s;
proxy_read_timeout 60s;

# Проксирование к OpenWebUI
proxy_pass http://openwebui_backend;
```

### searxng-api-common.conf

```nginx
# Rate limiting для SearXNG API
limit_req zone=searxng_api burst=30 nodelay;
limit_req_status 429;

# Кэширование SearXNG ответов
proxy_cache searxng_cache;
proxy_cache_valid 200 5m;
proxy_cache_key "$scheme$request_method$host$request_uri";

# URL rewriting для API
rewrite ^/api/searxng/(.*)$ /$1 break;

# Проксирование к SearXNG upstream
proxy_pass http://searxngUpstream;
proxy_set_header X-Request-ID $universal_request_id;

# Таймауты для поисковых запросов
proxy_connect_timeout 5s;
proxy_send_timeout 30s;
proxy_read_timeout 30s;
```

## 🔍 API эндпоинты

### Основные эндпоинты

| Эндпоинт              | Статус | Описание                   | Время ответа |
| --------------------- | ------ | -------------------------- | ------------ |
| `/health`             | ✅     | Проверка состояния системы | <100ms       |
| `/api/config`         | ✅     | Конфигурация системы       | <200ms       |
| `/api/searxng/search` | ✅     | RAG веб-поиск              | <2s          |
| `/api/mcp/`           | ✅     | Model Context Protocol     | <500ms       |
| WebSocket endpoints   | ✅     | Real-time коммуникация     | <50ms        |

### Примеры использования

```bash
# Проверка состояния системы
curl http://localhost:8080/health
# Ответ: {"status":true}

# SearXNG поиск для RAG
curl "http://localhost:8080/api/searxng/search?q=test&format=json"
# Ответ: JSON с результатами поиска (31 результат из 4500)

# Конфигурация системы
curl http://localhost:8080/api/config
# Ответ: JSON с настройками OpenWebUI
```

## 🛠️ Администрирование

### Применение изменений

```bash
# Проверка конфигурации
docker exec erni-ki-nginx-1 nginx -t

# Hot-reload без перезапуска
docker exec erni-ki-nginx-1 nginx -s reload

# Копирование include файлов
docker cp conf/nginx/includes/ erni-ki-nginx-1:/etc/nginx/
```

### Мониторинг

```bash
# Проверка логов
docker logs --tail=20 erni-ki-nginx-1

# Статус контейнера
docker ps | grep nginx

# Проверка портов
netstat -tlnp | grep nginx
```

## 🔧 Troubleshooting

### Частые проблемы

1. **404 на API эндпоинтах**
   - Проверить include файлы в контейнере
   - Убедиться в корректности upstream блоков

2. **WebSocket соединения не работают**
   - Проверить websocket-common.conf
   - Убедиться в наличии Upgrade заголовков

3. **SSL ошибки на localhost**
   - Проверить ssl_verify_client off
   - Убедиться в корректности CSP политики

### Диагностические команды

```bash
# Проверка nginx конфигурации
docker exec erni-ki-nginx-1 nginx -T

# Проверка upstream статуса
docker exec erni-ki-nginx-1 curl -s http://openwebui:8080/health

# Проверка include файлов
docker exec erni-ki-nginx-1 ls -la /etc/nginx/includes/
```

## 📊 Метрики производительности

- **Время ответа API:** <2 секунд
- **WebSocket latency:** <50ms
- **SSL handshake:** <100ms
- **Кэш hit ratio:** >80%
- **Rate limiting:** 60 req/s для SearXNG API

## 🔐 Безопасность

- **SSL/TLS:** TLSv1.2, TLSv1.3
- **HSTS:** max-age=31536000
- **CSP:** Оптимизированная для localhost и production
- **Rate limiting:** Защита от DDoS атак
- **CORS:** Настроенный для разрешенных доменов
