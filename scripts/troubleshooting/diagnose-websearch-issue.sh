#!/bin/bash

# Web Search Issue Diagnosis Script for ERNI-KI
# Скрипт диагностики проблем с веб-поиском в OpenWebUI

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
}

# Проверка доступности сервисов
check_services() {
    log "Проверка статуса сервисов..."
    
    echo "=== Docker Compose Services ==="
    docker-compose ps openwebui searxng nginx cloudflared auth
    echo ""
}

# Тестирование SearXNG напрямую
test_searxng_direct() {
    log "Тестирование SearXNG напрямую..."
    
    echo "=== Прямое подключение к SearXNG ==="
    
    # Тест через localhost:8081
    if curl -s -f http://localhost:8081/ >/dev/null; then
        success "SearXNG доступен через localhost:8081"
    else
        error "SearXNG недоступен через localhost:8081"
    fi
    
    # Тест поиска через localhost
    echo "Тестирование поиска через localhost..."
    local search_response
    search_response=$(curl -s -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "q=test&category_general=1&format=json" \
        http://localhost:8081/search)
    
    if echo "$search_response" | jq . >/dev/null 2>&1; then
        success "Поиск через localhost возвращает валидный JSON"
        echo "Количество результатов: $(echo "$search_response" | jq '.results | length')"
    else
        warning "Поиск через localhost не возвращает валидный JSON"
        echo "Ответ: ${search_response:0:200}..."
    fi
    echo ""
}

# Тестирование через Nginx proxy
test_nginx_proxy() {
    log "Тестирование через Nginx proxy..."
    
    echo "=== Тест через Nginx (localhost) ==="
    
    # Тест доступности через Nginx
    if curl -s -f -H "Host: localhost" http://localhost/searxng/ >/dev/null 2>&1; then
        success "SearXNG доступен через Nginx proxy (localhost)"
    else
        warning "SearXNG недоступен через Nginx proxy (localhost) - возможно требуется аутентификация"
    fi
    
    echo "=== Тест через Nginx (diz.zone) ==="
    
    # Тест через diz.zone (если доступен)
    if curl -s -f -k https://diz.zone/searxng/ >/dev/null 2>&1; then
        success "SearXNG доступен через diz.zone"
    else
        warning "SearXNG недоступен через diz.zone - возможно требуется аутентификация"
    fi
    echo ""
}

# Анализ конфигурации OpenWebUI
analyze_openwebui_config() {
    log "Анализ конфигурации OpenWebUI..."
    
    echo "=== Переменные окружения OpenWebUI ==="
    docker-compose exec -T openwebui env | grep -E "(SEARXNG|WEB_SEARCH|WEBUI_URL)" || echo "Переменные не найдены"
    
    echo ""
    echo "=== Проверка подключения OpenWebUI -> SearXNG ==="
    
    # Тест подключения изнутри контейнера OpenWebUI
    if docker-compose exec -T openwebui curl -s -f http://searxng:8080/ >/dev/null; then
        success "OpenWebUI может подключиться к SearXNG напрямую"
    else
        error "OpenWebUI не может подключиться к SearXNG"
    fi
    
    # Тест поиска изнутри OpenWebUI
    echo "Тестирование поиска изнутри OpenWebUI..."
    local internal_search
    internal_search=$(docker-compose exec -T openwebui curl -s -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "q=test&category_general=1&format=json" \
        http://searxng:8080/search)
    
    if echo "$internal_search" | jq . >/dev/null 2>&1; then
        success "Внутренний поиск OpenWebUI -> SearXNG работает"
    else
        warning "Внутренний поиск OpenWebUI -> SearXNG не работает"
        echo "Ответ: ${internal_search:0:200}..."
    fi
    echo ""
}

# Проверка Nginx конфигурации
check_nginx_config() {
    log "Проверка конфигурации Nginx..."
    
    echo "=== Nginx Configuration Test ==="
    if docker-compose exec -T nginx nginx -t; then
        success "Конфигурация Nginx валидна"
    else
        error "Ошибка в конфигурации Nginx"
    fi
    
    echo ""
    echo "=== Анализ маршрутов Nginx ==="
    echo "Проверка маршрута /searxng в конфигурации:"
    docker-compose exec -T nginx grep -A 10 -B 5 "searxng" /etc/nginx/conf.d/default.conf || echo "Маршрут не найден"
    echo ""
}

# Проверка логов
check_logs() {
    log "Анализ логов сервисов..."
    
    echo "=== Логи OpenWebUI (последние 20 строк) ==="
    docker-compose logs --tail=20 openwebui | grep -E "(search|searxng|error)" || echo "Релевантные записи не найдены"
    
    echo ""
    echo "=== Логи SearXNG (последние 20 строк) ==="
    docker-compose logs --tail=20 searxng | grep -E "(error|warning|search)" || echo "Релевантные записи не найдены"
    
    echo ""
    echo "=== Логи Nginx (последние 20 строк) ==="
    docker-compose logs --tail=20 nginx | grep -E "(searxng|error|upstream)" || echo "Релевантные записи не найдены"
    
    echo ""
    echo "=== Логи Cloudflared (последние 10 строк) ==="
    docker-compose logs --tail=10 cloudflared | grep -E "(error|tunnel)" || echo "Релевантные записи не найдены"
    echo ""
}

# Тестирование HTTP заголовков
test_http_headers() {
    log "Анализ HTTP заголовков..."
    
    echo "=== Заголовки localhost:8081 (прямое подключение) ==="
    curl -s -I http://localhost:8081/ | head -10
    
    echo ""
    echo "=== Заголовки через Nginx (localhost) ==="
    curl -s -I -H "Host: localhost" http://localhost/searxng/ | head -10 || echo "Недоступно"
    
    echo ""
    echo "=== Заголовки через diz.zone ==="
    curl -s -I -k https://diz.zone/searxng/ | head -10 || echo "Недоступно"
    echo ""
}

# Симуляция запроса веб-поиска
simulate_websearch() {
    log "Симуляция запроса веб-поиска..."
    
    echo "=== Симуляция запроса через localhost ==="
    local localhost_result
    localhost_result=$(curl -s -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "q=test search&category_general=1&format=json" \
        http://localhost:8081/search)
    
    echo "Размер ответа: $(echo "$localhost_result" | wc -c) байт"
    echo "Первые 200 символов: ${localhost_result:0:200}"
    
    if echo "$localhost_result" | jq . >/dev/null 2>&1; then
        success "Localhost возвращает валидный JSON"
    else
        warning "Localhost не возвращает валидный JSON"
    fi
    
    echo ""
    echo "=== Симуляция запроса через diz.zone (если доступен) ==="
    # Этот тест может не работать без аутентификации
    echo "Примечание: Тест через diz.zone требует аутентификации"
    echo ""
}

# Проверка сетевых подключений
check_network() {
    log "Проверка сетевых подключений..."
    
    echo "=== Docker Networks ==="
    docker network ls | grep erni-ki || echo "Сети не найдены"
    
    echo ""
    echo "=== Подключения контейнеров ==="
    echo "OpenWebUI -> SearXNG:"
    docker-compose exec -T openwebui nslookup searxng || echo "DNS не работает"
    
    echo ""
    echo "Nginx -> SearXNG:"
    docker-compose exec -T nginx nslookup searxng || echo "DNS не работает"
    echo ""
}

# Генерация отчета
generate_report() {
    log "Генерация отчета диагностики..."
    
    local report_file="websearch_diagnosis_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "Web Search Issue Diagnosis Report"
        echo "Generated: $(date)"
        echo "================================="
        echo ""
        
        echo "PROBLEM DESCRIPTION:"
        echo "- Web search works via localhost/local IPs"
        echo "- Web search fails via diz.zone domain"
        echo "- Error: SyntaxError: JSON.parse: unexpected character"
        echo ""
        
        echo "CURRENT CONFIGURATION:"
        echo "- SEARXNG_QUERY_URL: $(docker-compose exec -T openwebui env | grep SEARXNG_QUERY_URL || echo 'Not set')"
        echo "- WEBUI_URL: $(docker-compose exec -T openwebui env | grep WEBUI_URL || echo 'Not set')"
        echo "- WEB_SEARCH_ENGINE: $(docker-compose exec -T openwebui env | grep WEB_SEARCH_ENGINE || echo 'Not set')"
        echo ""
        
        echo "SERVICE STATUS:"
        docker-compose ps openwebui searxng nginx cloudflared auth
        echo ""
        
        echo "NGINX SEARXNG ROUTE:"
        docker-compose exec -T nginx grep -A 15 -B 5 "searxng" /etc/nginx/conf.d/default.conf || echo "Route not found"
        echo ""
        
        echo "RECENT ERRORS:"
        echo "OpenWebUI errors:"
        docker-compose logs --tail=50 openwebui | grep -i error | tail -10 || echo "No errors found"
        echo ""
        echo "SearXNG errors:"
        docker-compose logs --tail=50 searxng | grep -i error | tail -10 || echo "No errors found"
        echo ""
        echo "Nginx errors:"
        docker-compose logs --tail=50 nginx | grep -i error | tail -10 || echo "No errors found"
        
    } > "$report_file"
    
    success "Отчет сохранен в: $report_file"
}

# Основная функция
main() {
    log "Запуск диагностики проблем с веб-поиском..."
    
    # Проверка, что мы в корне проекта
    if [ ! -f "compose.yml" ] && [ ! -f "docker-compose.yml" ]; then
        error "Файл compose.yml не найден. Запустите скрипт из корня проекта."
        exit 1
    fi
    
    check_services
    test_searxng_direct
    test_nginx_proxy
    analyze_openwebui_config
    check_nginx_config
    check_logs
    test_http_headers
    simulate_websearch
    check_network
    generate_report
    
    echo ""
    log "Диагностика завершена. Основные проблемы:"
    echo "1. Маршрут /searxng в Nginx требует аутентификации"
    echo "2. OpenWebUI делает внутренние API запросы, которые блокируются"
    echo "3. Необходимо создать отдельный маршрут для API без аутентификации"
    echo ""
    warning "Рекомендация: Запустите ./scripts/fix-websearch-issue.sh для исправления"
}

# Запуск скрипта
main "$@"
