#!/bin/bash

# SearXNG Integration Test Script for ERNI-KI
# Скрипт тестирования интеграции SearXNG в проекте ERNI-KI

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

# Проверка доступности SearXNG
test_searxng_availability() {
    log "Тестирование доступности SearXNG..."

    # Прямое подключение к контейнеру
    if curl -f -s http://localhost:8081/ >/dev/null; then
        success "SearXNG доступен напрямую (порт 8081)"
    else
        error "SearXNG недоступен напрямую"
        return 1
    fi

    # Проверка через Nginx (если настроен)
    if curl -f -s -H "Host: localhost" http://localhost/searxng/ >/dev/null 2>&1; then
        success "SearXNG доступен через Nginx proxy"
    else
        warning "SearXNG недоступен через Nginx proxy (возможно, требуется аутентификация)"
    fi
}

# Тестирование поиска
test_search_functionality() {
    log "Тестирование функциональности поиска..."

    local search_query="test search"
    local search_url="http://localhost:8081/search"

    # POST запрос для поиска
    local response
    response=$(curl -s -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "q=${search_query}&category_general=1&language=auto&time_range=&safesearch=0&theme=simple" \
        "$search_url")

    if echo "$response" | grep -q "search results" || echo "$response" | grep -q "результат"; then
        success "Поиск работает корректно"
    else
        warning "Поиск может работать некорректно (проверьте логи)"
    fi
}

# Проверка Redis подключения
test_redis_connection() {
    log "Проверка подключения к Redis..."

    if docker-compose exec -T redis redis-cli ping | grep -q "PONG"; then
        success "Redis доступен"
    else
        error "Redis недоступен"
        return 1
    fi

    # Проверка подключения SearXNG к Redis
    if docker-compose logs searxng | grep -q "redis" && ! docker-compose logs searxng | grep -q "redis.*error"; then
        success "SearXNG успешно подключен к Redis"
    else
        warning "Возможны проблемы с подключением SearXNG к Redis"
    fi
}

# Проверка health check
test_health_checks() {
    log "Проверка health checks..."

    local health_status
    health_status=$(docker-compose ps searxng --format "table {{.Name}}\t{{.Status}}")

    if echo "$health_status" | grep -q "healthy"; then
        success "Health check SearXNG проходит успешно"
    elif echo "$health_status" | grep -q "unhealthy"; then
        error "Health check SearXNG не проходит"
        return 1
    else
        warning "Статус health check неопределен"
    fi
}

# Проверка логов на ошибки
check_logs_for_errors() {
    log "Проверка логов на критические ошибки..."

    local logs
    logs=$(docker-compose logs --tail=50 searxng)

    # Проверка на критические ошибки
    if echo "$logs" | grep -i "error\|exception\|failed\|critical"; then
        warning "Обнаружены ошибки в логах SearXNG:"
        echo "$logs" | grep -i "error\|exception\|failed\|critical" | tail -5
    else
        success "Критические ошибки в логах не обнаружены"
    fi

    # Проверка на предупреждения о limiter.toml
    if echo "$logs" | grep -q "missing config file.*limiter.toml"; then
        warning "Отсутствует файл limiter.toml (это нормально, если он не монтируется)"
    fi
}

# Тестирование интеграции с OpenWebUI
test_openwebui_integration() {
    log "Тестирование интеграции с OpenWebUI..."

    # Проверка переменных окружения OpenWebUI
    local openwebui_env
    if openwebui_env=$(docker-compose exec -T openwebui env | grep SEARXNG); then
        success "Переменные окружения SearXNG настроены в OpenWebUI:"
        echo "$openwebui_env"
    else
        warning "Переменные окружения SearXNG не найдены в OpenWebUI"
    fi

    # Проверка доступности SearXNG из контейнера OpenWebUI
    if docker-compose exec -T openwebui curl -f -s http://searxng:8080/ >/dev/null; then
        success "OpenWebUI может подключиться к SearXNG"
    else
        error "OpenWebUI не может подключиться к SearXNG"
        return 1
    fi
}

# Проверка производительности
test_performance() {
    log "Тестирование производительности..."

    local start_time end_time duration
    start_time=$(date +%s.%N)

    curl -s -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "q=performance test&category_general=1" \
        "http://localhost:8081/search" >/dev/null

    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc)

    if (( $(echo "$duration < 5.0" | bc -l) )); then
        success "Время ответа поиска: ${duration}s (хорошо)"
    elif (( $(echo "$duration < 10.0" | bc -l) )); then
        warning "Время ответа поиска: ${duration}s (приемлемо)"
    else
        warning "Время ответа поиска: ${duration}s (медленно)"
    fi
}

# Проверка безопасности
test_security_features() {
    log "Проверка функций безопасности..."

    # Проверка заголовков безопасности
    local headers
    headers=$(curl -s -I http://localhost:8081/)

    if echo "$headers" | grep -q "X-Content-Type-Options"; then
        success "Заголовки безопасности настроены"
    else
        warning "Заголовки безопасности могут быть не настроены"
    fi

    # Проверка rate limiting (если настроен)
    log "Проверка rate limiting..."
    local rate_limit_test=0
    for i in {1..15}; do
        if curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/ | grep -q "429"; then
            rate_limit_test=1
            break
        fi
        sleep 0.1
    done

    if [ $rate_limit_test -eq 1 ]; then
        success "Rate limiting работает"
    else
        warning "Rate limiting может быть не настроен или не активен"
    fi
}

# Генерация отчета
generate_report() {
    log "Генерация отчета тестирования..."

    local report_file="searxng_test_report_$(date +%Y%m%d_%H%M%S).txt"

    {
        echo "SearXNG Integration Test Report"
        echo "Generated: $(date)"
        echo "================================"
        echo ""

        echo "Container Status:"
        docker-compose ps searxng nginx redis
        echo ""

        echo "SearXNG Configuration:"
        echo "- Image: $(docker-compose images searxng | tail -1 | awk '{print $2":"$3}')"
        echo "- Ports: $(docker-compose port searxng 8080 2>/dev/null || echo 'Not exposed')"
        echo ""

        echo "Recent Logs (last 20 lines):"
        docker-compose logs --tail=20 searxng
        echo ""

        echo "Environment Variables:"
        docker-compose exec -T searxng env | grep SEARXNG || echo "No SEARXNG env vars found"

    } > "$report_file"

    success "Отчет сохранен в: $report_file"
}

# Основная функция
main() {
    log "Запуск тестирования интеграции SearXNG..."

    # Проверка, что мы в корне проекта
    if [ ! -f "compose.yml" ] && [ ! -f "docker-compose.yml" ]; then
        error "Файл compose.yml или docker-compose.yml не найден"
    fi

    local failed_tests=0

    # Выполнение тестов
    test_searxng_availability || ((failed_tests++))
    test_search_functionality || ((failed_tests++))
    test_redis_connection || ((failed_tests++))
    test_health_checks || ((failed_tests++))
    check_logs_for_errors
    test_openwebui_integration || ((failed_tests++))
    test_performance
    test_security_features

    generate_report

    echo ""
    if [ $failed_tests -eq 0 ]; then
        success "Все критические тесты пройдены успешно!"
    else
        warning "$failed_tests критических тестов не пройдено"
    fi

    log "Рекомендации:"
    echo "1. Проверьте логи: docker-compose logs searxng"
    echo "2. Убедитесь, что все сервисы запущены: docker-compose ps"
    echo "3. Проверьте конфигурацию: docker-compose config"
    echo "4. Для отладки: docker-compose exec searxng sh"
}

# Запуск скрипта
main "$@"
