#!/bin/bash

# Web Search Domain Diagnosis Script for ERNI-KI
# Скрипт диагностики веб-поиска через разные домены

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

# Функция проверки JSON
check_json() {
    local response="$1"
    local domain="$2"

    if echo "$response" | jq . >/dev/null 2>&1; then
        local result_count=$(echo "$response" | jq '.results | length' 2>/dev/null || echo "0")
        success "$domain: Валидный JSON, $result_count результатов"
        return 0
    else
        error "$domain: Невалидный JSON"
        echo "Первые 200 символов ответа:"
        echo "${response:0:200}"
        return 1
    fi
}

# Функция тестирования API endpoint
test_api_endpoint() {
    local domain="$1"
    local host_header="$2"

    log "Тестирование API endpoint для $domain..."

    local cmd="curl -k -s -w 'HTTP_CODE:%{http_code}' -X POST"
    if [ "$host_header" != "none" ]; then
        cmd="$cmd -H 'Host: $host_header'"
    fi
    cmd="$cmd -H 'Content-Type: application/x-www-form-urlencoded'"
    cmd="$cmd -d 'q=test&format=json'"
    cmd="$cmd https://localhost/api/searxng/search"

    local response
    if response=$(eval "$cmd" 2>/dev/null); then
        local http_code="${response##*HTTP_CODE:}"
        local json_response="${response%HTTP_CODE:*}"

        echo "  HTTP код: $http_code"

        if [ "$http_code" = "200" ]; then
            check_json "$json_response" "$domain"
        else
            error "$domain: HTTP ошибка $http_code"
            echo "  Ответ: ${json_response:0:200}"
            return 1
        fi
    else
        error "$domain: Не удалось выполнить запрос"
        return 1
    fi
}

# Функция тестирования основного интерфейса
test_main_interface() {
    local domain="$1"
    local host_header="$2"

    log "Тестирование основного интерфейса для $domain..."

    local cmd="curl -k -s -w 'HTTP_CODE:%{http_code}'"
    if [ "$host_header" != "none" ]; then
        cmd="$cmd -H 'Host: $host_header'"
    fi
    cmd="$cmd https://localhost/"

    local response
    if response=$(eval "$cmd" 2>/dev/null); then
        local http_code="${response##*HTTP_CODE:}"

        echo "  HTTP код: $http_code"

        if [ "$http_code" = "200" ]; then
            success "$domain: Основной интерфейс доступен"
            return 0
        else
            warning "$domain: HTTP код $http_code"
            return 1
        fi
    else
        error "$domain: Основной интерфейс недоступен"
        return 1
    fi
}

# Функция проверки конфигурации Nginx
check_nginx_config() {
    log "Проверка конфигурации Nginx..."

    echo "=== Server Names ==="
    docker-compose exec nginx grep -A 2 "server_name" /etc/nginx/conf.d/default.conf || true

    echo ""
    echo "=== API Endpoint Configuration ==="
    docker-compose exec nginx grep -A 10 "location /api/searxng" /etc/nginx/conf.d/default.conf || true

    echo ""
    echo "=== Nginx Syntax Check ==="
    if docker-compose exec nginx nginx -t 2>/dev/null; then
        success "Nginx конфигурация валидна"
    else
        error "Ошибка в конфигурации Nginx"
    fi
}

# Функция проверки переменных окружения
check_environment() {
    log "Проверка переменных окружения OpenWebUI..."

    echo "=== SEARXNG Configuration ==="
    grep -E "(SEARXNG|WEB_SEARCH)" env/openwebui.env || true

    echo ""
    echo "=== WEBUI_URL ==="
    grep "WEBUI_URL" env/openwebui.env || true
}

# Функция проверки статуса сервисов
check_services() {
    log "Проверка статуса сервисов..."

    echo "=== Docker Compose Status ==="
    docker-compose ps nginx openwebui searxng

    echo ""
    echo "=== Health Checks ==="
    local nginx_health=$(docker-compose ps nginx --format "table {{.Status}}" | tail -1)
    local openwebui_health=$(docker-compose ps openwebui --format "table {{.Status}}" | tail -1)
    local searxng_health=$(docker-compose ps searxng --format "table {{.Status}}" | tail -1)

    echo "Nginx: $nginx_health"
    echo "OpenWebUI: $openwebui_health"
    echo "SearXNG: $searxng_health"
}

# Функция проверки логов
check_logs() {
    log "Проверка логов сервисов..."

    echo "=== Nginx Logs (последние 5 строк) ==="
    docker-compose logs --tail=5 nginx 2>/dev/null || echo "Не удалось получить логи Nginx"

    echo ""
    echo "=== OpenWebUI Logs (последние 5 строк) ==="
    docker-compose logs --tail=5 openwebui 2>/dev/null || echo "Не удалось получить логи OpenWebUI"

    echo ""
    echo "=== SearXNG Logs (последние 5 строк) ==="
    docker-compose logs --tail=5 searxng 2>/dev/null || echo "Не удалось получить логи SearXNG"
}

# Функция симуляции проблемы
simulate_problem() {
    log "Симуляция проблемы с JSON.parse..."

    # Тестируем что происходит, если API возвращает HTML вместо JSON
    echo "=== Тест: что если API возвращает HTML? ==="

    local html_response='<!DOCTYPE html><html><head><title>Error</title></head><body><h1>Authentication Required</h1></body></html>'

    echo "HTML ответ:"
    echo "$html_response"

    echo ""
    echo "Попытка парсинга как JSON:"
    if echo "$html_response" | jq . >/dev/null 2>&1; then
        echo "✅ JSON валиден"
    else
        echo "❌ JSON невалиден - это вызовет SyntaxError: JSON.parse"
    fi
}

# Основная функция диагностики
main() {
    echo "=================================================="
    echo "🔍 ДИАГНОСТИКА ВЕБ-ПОИСКА ЧЕРЕЗ РАЗНЫЕ ДОМЕНЫ"
    echo "=================================================="
    echo "Время: $(date)"
    echo ""

    # Проверка зависимостей
    if ! command -v jq >/dev/null 2>&1; then
        error "jq не установлен. Установите: sudo apt-get install jq"
        exit 1
    fi

    # 1. Проверка конфигурации
    check_nginx_config
    echo ""

    # 2. Проверка переменных окружения
    check_environment
    echo ""

    # 3. Проверка статуса сервисов
    check_services
    echo ""

    # 4. Тестирование API endpoints
    echo "=================================================="
    echo "🧪 ТЕСТИРОВАНИЕ API ENDPOINTS"
    echo "=================================================="

    test_api_endpoint "localhost" "none"
    echo ""

    test_api_endpoint "diz.zone" "diz.zone"
    echo ""

    test_api_endpoint "webui.diz.zone" "webui.diz.zone"
    echo ""

    # 5. Тестирование основных интерфейсов
    echo "=================================================="
    echo "🌐 ТЕСТИРОВАНИЕ ОСНОВНЫХ ИНТЕРФЕЙСОВ"
    echo "=================================================="

    test_main_interface "localhost" "none"
    echo ""

    test_main_interface "diz.zone" "diz.zone"
    echo ""

    test_main_interface "webui.diz.zone" "webui.diz.zone"
    echo ""

    # 6. Проверка логов
    check_logs
    echo ""

    # 7. Симуляция проблемы
    simulate_problem
    echo ""

    # 8. Рекомендации
    echo "=================================================="
    echo "💡 РЕКОМЕНДАЦИИ"
    echo "=================================================="

    echo "1. Если все API endpoints работают, проблема может быть:"
    echo "   - В браузере (кэш, cookies)"
    echo "   - В Cloudflare настройках"
    echo "   - В аутентификации через веб-интерфейс"
    echo ""

    echo "2. Для дальнейшей диагностики:"
    echo "   - Проверьте Network tab в браузере"
    echo "   - Очистите кэш браузера"
    echo "   - Проверьте Cloudflare логи"
    echo ""

    echo "3. Если проблема воспроизводится:"
    echo "   - Сохраните точный HTTP запрос из браузера"
    echo "   - Проверьте заголовки аутентификации"
    echo "   - Сравните с работающими запросами"

    # Сохранение отчета
    local report_file="websearch_diagnosis_$(date +%Y%m%d_%H%M%S).txt"
    {
        echo "Web Search Domain Diagnosis Report"
        echo "Generated: $(date)"
        echo "======================================"
        echo ""
        echo "SUMMARY:"
        echo "- API endpoints tested: localhost, diz.zone, webui.diz.zone"
        echo "- Configuration checked: Nginx, OpenWebUI environment"
        echo "- Services status verified"
        echo ""
        echo "For detailed results, see terminal output above."
    } > "$report_file"

    log "Отчет сохранен в: $report_file"
}

# Запуск диагностики
main "$@"
