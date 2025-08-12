#!/bin/bash

# Скрипт мониторинга rate limiting для nginx ERNI-KI
# Автор: Альтэон Шульц, Tech Lead-Мудрец
# Версия: 1.0

set -euo pipefail

# Конфигурация
NGINX_CONTAINER="erni-ki-nginx-1"
LOG_DIR="/var/log/nginx"
ALERT_THRESHOLD=80  # Процент от лимита для алерта

# Цвета для вывода
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "=== ERNI-KI Rate Limiting Monitor ==="
echo "Время: $(date '+%Y-%m-%d %H:%M:%S')"
echo

# Функция для получения статистики запросов за последние 5 минут
get_request_stats() {
    local endpoint="$1"
    local time_window="5m"

    echo "📊 Статистика запросов к $endpoint за последние $time_window:"

    # Общее количество запросов
    local total_requests=$(docker logs --since=$time_window $NGINX_CONTAINER 2>/dev/null | \
        grep -c "$endpoint" | tr -d '\n' || echo "0")

    # Количество 429 ошибок (rate limited)
    local rate_limited=$(docker logs --since=$time_window $NGINX_CONTAINER 2>/dev/null | \
        grep "$endpoint" | grep " 429 " | wc -l | tr -d '\n' || echo "0")

    # Количество 5xx ошибок
    local server_errors=$(docker logs --since=$time_window $NGINX_CONTAINER 2>/dev/null | \
        grep "$endpoint" | grep " 5[0-9][0-9] " | wc -l | tr -d '\n' || echo "0")

    echo "  Всего запросов: $total_requests"
    echo "  Rate limited (429): $rate_limited"
    echo "  Серверные ошибки (5xx): $server_errors"

    # Расчет процента rate limiting
    if [ "$total_requests" -gt 0 ]; then
        local rate_limit_percent=$((rate_limited * 100 / total_requests))

        if [ "$rate_limit_percent" -ge "$ALERT_THRESHOLD" ]; then
            echo -e "  ${RED}⚠️  АЛЕРТ: Rate limiting ${rate_limit_percent}% >= ${ALERT_THRESHOLD}%${NC}"
        elif [ "$rate_limit_percent" -ge 50 ]; then
            echo -e "  ${YELLOW}⚠️  Предупреждение: Rate limiting ${rate_limit_percent}%${NC}"
        else
            echo -e "  ${GREEN}✅ Rate limiting: ${rate_limit_percent}%${NC}"
        fi
    fi
    echo
}

# Функция для проверки размера логов
check_log_sizes() {
    echo "📁 Размеры логов nginx:"

    docker exec $NGINX_CONTAINER ls -lh $LOG_DIR/ 2>/dev/null | \
        grep -E "\.(log|json)$" | \
        awk '{print "  " $9 ": " $5}' || echo "  Ошибка доступа к логам"
    echo
}

# Функция для показа топ IP адресов
show_top_ips() {
    echo "🌐 Топ 10 IP адресов за последние 5 минут:"

    docker logs --since=5m $NGINX_CONTAINER 2>/dev/null | \
        awk '{print $1}' | \
        sort | uniq -c | sort -nr | head -10 | \
        awk '{printf "  %s: %d запросов\n", $2, $1}' || echo "  Нет данных"
    echo
}

# Функция для показа статуса nginx
show_nginx_status() {
    echo "🔧 Статус nginx:"

    # Проверка работы контейнера
    if docker ps --filter "name=$NGINX_CONTAINER" --filter "status=running" | grep -q $NGINX_CONTAINER; then
        echo -e "  ${GREEN}✅ Контейнер работает${NC}"
    else
        echo -e "  ${RED}❌ Контейнер не работает${NC}"
        return 1
    fi

    # Проверка конфигурации
    if docker exec $NGINX_CONTAINER nginx -t >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅ Конфигурация валидна${NC}"
    else
        echo -e "  ${RED}❌ Ошибка в конфигурации${NC}"
    fi

    # Проверка доступности
    if curl -k -s -o /dev/null -w "%{http_code}" https://localhost/ | grep -q "200"; then
        echo -e "  ${GREEN}✅ HTTPS доступен${NC}"
    else
        echo -e "  ${YELLOW}⚠️  HTTPS недоступен${NC}"
    fi
    echo
}

# Основная логика
main() {
    show_nginx_status

    # Статистика по основным endpoints
    get_request_stats "/api/health"
    get_request_stats "/api/chat"
    get_request_stats "/api/v1/files"
    get_request_stats "/api/searxng"

    show_top_ips
    check_log_sizes

    echo "=== Мониторинг завершен ==="
}

# Запуск
main "$@"
