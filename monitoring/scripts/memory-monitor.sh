#!/bin/bash

# Memory Monitor для ERNI-KI
# Мониторинг критического использования памяти контейнерами

set -euo pipefail

# Конфигурация
ELASTICSEARCH_THRESHOLD=95
LITELLM_THRESHOLD=90
GENERAL_THRESHOLD=85
LOG_FILE="./logs/memory-monitor.log"
WEBHOOK_URL="${WEBHOOK_URL:-}"

# Функция логирования
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Функция отправки уведомлений
send_alert() {
    local container="$1"
    local usage="$2"
    local threshold="$3"
    local message="🚨 CRITICAL: Container $container memory usage: ${usage}% (threshold: ${threshold}%)"

    log "ALERT: $message"

    # Отправка webhook уведомления если настроен
    if [[ -n "$WEBHOOK_URL" ]]; then
        curl -s -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"$message\",\"severity\":\"critical\",\"service\":\"$container\"}" \
            || log "Failed to send webhook notification"
    fi

    # Системное уведомление
    echo "$message" | wall 2>/dev/null || true
}

# Функция получения использования памяти контейнера
get_memory_usage() {
    local container="$1"
    docker stats --no-stream --format "{{.MemPerc}}" "$container" 2>/dev/null | sed 's/%//' || echo "0"
}

# Функция проверки контейнера
check_container() {
    local container="$1"
    local threshold="$2"

    if ! docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        log "WARNING: Container $container not found or not running"
        return 1
    fi

    local usage
    usage=$(get_memory_usage "$container")

    if [[ -z "$usage" ]] || [[ "$usage" == "0" ]]; then
        log "WARNING: Could not get memory usage for $container"
        return 1
    fi

    log "Container $container memory usage: ${usage}%"

    # Проверка превышения порога
    if (( $(echo "$usage > $threshold" | bc -l) )); then
        send_alert "$container" "$usage" "$threshold"
        return 2
    fi

    return 0
}

# Функция проверки всех контейнеров
check_all_containers() {
    local alerts=0

    log "Starting memory monitoring check..."

    # Проверка Elasticsearch
    if check_container "erni-ki-elasticsearch" "$ELASTICSEARCH_THRESHOLD"; then
        log "Elasticsearch memory usage OK"
    else
        case $? in
            2) ((alerts++)) ;;
            *) log "Elasticsearch check failed" ;;
        esac
    fi

    # Проверка LiteLLM
    if check_container "erni-ki-litellm" "$LITELLM_THRESHOLD"; then
        log "LiteLLM memory usage OK"
    else
        case $? in
            2) ((alerts++)) ;;
            *) log "LiteLLM check failed" ;;
        esac
    fi

    # Проверка других критических контейнеров
    local containers=("erni-ki-openwebui-1" "erni-ki-ollama-1" "erni-ki-db-1")

    for container in "${containers[@]}"; do
        if check_container "$container" "$GENERAL_THRESHOLD"; then
            log "$container memory usage OK"
        else
            case $? in
                2) ((alerts++)) ;;
                *) log "$container check failed" ;;
            esac
        fi
    done

    log "Memory monitoring check completed. Alerts: $alerts"
    return $alerts
}

# Функция получения общей статистики системы
get_system_stats() {
    log "=== System Memory Statistics ==="

    # Общая память системы
    local total_mem
    total_mem=$(free -h | awk '/^Mem:/ {print $2}')
    local used_mem
    used_mem=$(free -h | awk '/^Mem:/ {print $3}')
    local free_mem
    free_mem=$(free -h | awk '/^Mem:/ {print $4}')

    log "System Memory - Total: $total_mem, Used: $used_mem, Free: $free_mem"

    # Топ контейнеров по использованию памяти
    log "Top 5 containers by memory usage:"
    docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}" | head -6 | while read -r line; do
        log "  $line"
    done
}

# Основная функция
main() {
    # Создание директории для логов
    mkdir -p "$(dirname "$LOG_FILE")"

    log "=== ERNI-KI Memory Monitor Started ==="

    # Получение системной статистики
    get_system_stats

    # Проверка контейнеров
    local alert_count=0
    if ! check_all_containers; then
        alert_count=$?
    fi

    # Итоговый отчет
    if [[ $alert_count -gt 0 ]]; then
        log "=== CRITICAL: $alert_count memory alerts detected! ==="
        exit 1
    else
        log "=== All containers within memory limits ==="
        exit 0
    fi
}

# Запуск если скрипт вызван напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
