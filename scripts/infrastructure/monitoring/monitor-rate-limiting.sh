#!/bin/bash

# ERNI-KI Rate Limiting Monitor
# Мониторинг и анализ rate limiting событий в nginx
# Автор: Альтэон Шульц (Tech Lead)

set -euo pipefail

# === Конфигурация ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LOG_FILE="$PROJECT_ROOT/logs/rate-limiting-monitor.log"
STATE_FILE="$PROJECT_ROOT/logs/rate-limiting-state.json"
ALERT_THRESHOLD=10  # Алерт при >10 блокировок в минуту
WARNING_THRESHOLD=5 # Предупреждение при >5 блокировок в минуту
CHECK_INTERVAL=60   # Интервал проверки в секундах
NGINX_ACCESS_LOG="${NGINX_ACCESS_LOG:-$PROJECT_ROOT/data/nginx/logs/access.log}"
COMPOSE_BIN="${DOCKER_COMPOSE_BIN:-docker compose}"

# Создание директории для логов
mkdir -p "$(dirname "$LOG_FILE")"

# === Функции логирования ===
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $*" | tee -a "$LOG_FILE"
}

warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*" | tee -a "$LOG_FILE"
}

# === Функция анализа rate limiting ===
analyze_rate_limiting() {
    local time_window="${1:-1m}"  # По умолчанию последняя минута

    log "Анализ rate limiting за последние $time_window"

    # Получение логов nginx за указанный период
    local nginx_logs
    nginx_logs=$($COMPOSE_BIN -f "$PROJECT_ROOT/compose.yml" logs nginx --since "$time_window" 2>/dev/null || echo "")

    if [[ -z "$nginx_logs" && -f "$NGINX_ACCESS_LOG" ]]; then
        nginx_logs=$(tail -n 2000 "$NGINX_ACCESS_LOG" | grep "$(date -u +"%d/%b/%Y:%H:%M")" || true)
    fi

    if [[ -z "$nginx_logs" ]]; then
        log "Нет логов nginx за указанный период"
        return 0
    fi

    # Подсчет rate limiting ошибок
    local total_blocks
    total_blocks=$(echo "$nginx_logs" | grep -c "limiting requests" | tr -d '\n' || echo "0")

    # Анализ по зонам
    local zones_stats
    zones_stats=$(echo "$nginx_logs" | grep "limiting requests" | grep -o 'zone "[^"]*"' | sort | uniq -c || echo "")

    # Анализ по IP адресам
    local ip_stats
    ip_stats=$(echo "$nginx_logs" | grep "limiting requests" | grep -o 'client: [^,]*' | sort | uniq -c | head -10 || echo "")

    # Максимальное превышение
    local max_excess
    max_excess=$(echo "$nginx_logs" | grep "limiting requests" | grep -o 'excess: [0-9.]*' | sort -n | tail -1 | tr -d '\n' || echo "0")

    # Создание JSON отчета
    local report
    report=$(cat <<EOF
{
    "timestamp": "$(date -Iseconds)",
    "time_window": "$time_window",
    "total_blocks": $total_blocks,
    "max_excess": "${max_excess#excess: }",
    "zones": $(echo "$zones_stats" | awk '{print "{\"zone\":\""$2"\",\"count\":"$1"}"}' | jq -s '.' 2>/dev/null || echo "[]"),
    "top_ips": $(echo "$ip_stats" | awk '{print "{\"ip\":\""$3"\",\"count\":"$1"}"}' | jq -s '.' 2>/dev/null || echo "[]")
}
EOF
    )

    # Сохранение состояния
    echo "$report" > "$STATE_FILE"

    # Логирование результатов
    log "Rate limiting статистика:"
    log "  - Всего блокировок: $total_blocks"
    log "  - Максимальное превышение: ${max_excess#excess: }"

    if [[ -n "$zones_stats" ]]; then
        log "  - По зонам:"
        echo "$zones_stats" | while read -r count zone; do
            log "    $zone: $count блокировок"
        done
    fi

    # Проверка порогов и отправка алертов
    check_thresholds "$total_blocks" "$report"

    return 0
}

# === Функция проверки порогов ===
check_thresholds() {
    local total_blocks="$1"
    local report="$2"

    if [[ $total_blocks -ge $ALERT_THRESHOLD ]]; then
        send_alert "CRITICAL" "Rate limiting превысил критический порог: $total_blocks блокировок в минуту (порог: $ALERT_THRESHOLD)" "$report"
    elif [[ $total_blocks -ge $WARNING_THRESHOLD ]]; then
        send_alert "WARNING" "Rate limiting превысил предупредительный порог: $total_blocks блокировок в минуту (порог: $WARNING_THRESHOLD)" "$report"
    fi
}

# === Функция отправки алертов ===
send_alert() {
    local level="$1"
    local message="$2"
    local report="$3"

    log "[$level] $message"

    # Отправка через системный журнал
    logger -t "erni-ki-rate-limiting" "[$level] $message"

    # Сохранение алерта в файл
    local alert_file="$PROJECT_ROOT/logs/rate-limiting-alerts.log"
    echo "[$(date -Iseconds)] [$level] $message" >> "$alert_file"
    echo "$report" >> "$alert_file"
    echo "---" >> "$alert_file"

    # Интеграция с Backrest (если доступен)
    if command -v curl >/dev/null 2>&1; then
        send_backrest_notification "$level" "$message" || true
    fi
}

# === Функция отправки уведомлений через Backrest ===
send_backrest_notification() {
    local level="$1"
    local message="$2"

    # Попытка отправки через Backrest webhook (если настроен)
    local backrest_url="http://localhost:9898/api/v1/notifications"

    local payload
    payload=$(cat <<EOF
{
    "title": "ERNI-KI Rate Limiting Alert",
    "message": "$message",
    "level": "$level",
    "timestamp": "$(date -Iseconds)",
    "source": "nginx-rate-limiting-monitor"
}
EOF
    )

    if curl -s -f -X POST "$backrest_url" \
        -H "Content-Type: application/json" \
        -d "$payload" >/dev/null 2>&1; then
        log "Уведомление отправлено через Backrest"
    else
        log "Не удалось отправить уведомление через Backrest"
    fi
}

# === Функция получения статистики ===
get_statistics() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo '{"error": "Нет данных статистики"}'
    fi
}

# === Функция проверки здоровья nginx ===
check_nginx_health() {
    log "Проверка здоровья nginx..."

    if $COMPOSE_BIN -f "$PROJECT_ROOT/compose.yml" exec -T nginx nginx -t >/dev/null 2>&1; then
        success "Конфигурация nginx корректна"
    else
        error "Ошибка в конфигурации nginx"
        return 1
    fi

    # Проверка доступности
    if curl -s -f http://localhost/ >/dev/null 2>&1; then
        success "Nginx отвечает на запросы"
    else
        error "Nginx не отвечает на запросы"
        return 1
    fi

    return 0
}

# === Основная функция ===
main() {
    case "${1:-monitor}" in
        "monitor")
            log "Запуск мониторинга rate limiting"
            analyze_rate_limiting "1m"
            ;;
        "stats")
            get_statistics
            ;;
        "health")
            check_nginx_health
            ;;
        "daemon")
            log "Запуск демона мониторинга (интервал: ${CHECK_INTERVAL}s)"
            while true; do
                analyze_rate_limiting "1m"
                sleep "$CHECK_INTERVAL"
            done
            ;;
        "help"|"-h"|"--help")
            cat <<EOF
ERNI-KI Rate Limiting Monitor

Использование:
  $0 [команда]

Команды:
  monitor    Однократная проверка rate limiting (по умолчанию)
  stats      Показать последнюю статистику
  health     Проверить здоровье nginx
  daemon     Запустить в режиме демона
  help       Показать эту справку

Примеры:
  $0                    # Однократная проверка
  $0 daemon            # Запуск в режиме демона
  $0 stats | jq        # Показать статистику в JSON
EOF
            ;;
        *)
            error "Неизвестная команда: $1"
            echo "Используйте '$0 help' для справки"
            exit 1
            ;;
    esac
}

# Запуск основной функции
main "$@"
