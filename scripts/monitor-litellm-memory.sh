#!/bin/bash

# LiteLLM Memory Monitoring Script для ERNI-KI
# Автоматическая проверка использования памяти каждые 5 минут
# Создан: 2025-09-09 для решения критической проблемы с памятью

set -euo pipefail

# Конфигурация
CONTAINER_NAME="erni-ki-litellm"
MEMORY_THRESHOLD=90  # Процент использования памяти для алерта
LOG_FILE="/var/log/litellm-memory-monitor.log"
WEBHOOK_URL=""  # Опционально: URL для уведомлений

# Функция логирования
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Функция отправки уведомления
send_alert() {
    local message="$1"
    local memory_usage="$2"

    log "ALERT: $message (Memory: $memory_usage%)"

    # Отправка в webhook (если настроен)
    if [[ -n "$WEBHOOK_URL" ]]; then
        curl -s -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"🚨 ERNI-KI LiteLLM Memory Alert: $message (Memory: $memory_usage%)\",\"channel\":\"#alerts\"}" \
            || log "Failed to send webhook notification"
    fi

    # Отправка в системный журнал
    logger -t "litellm-monitor" "CRITICAL: $message (Memory: $memory_usage%)"
}

# Функция проверки памяти
check_memory() {
    # Получить статистику контейнера
    local stats
    if ! stats=$(docker stats --no-stream --format "{{.MemPerc}}" "$CONTAINER_NAME" 2>/dev/null); then
        log "ERROR: Cannot get stats for container $CONTAINER_NAME"
        return 1
    fi

    # Извлечь процент использования памяти
    local memory_percent
    memory_percent=$(echo "$stats" | sed 's/%//')

    # Проверить, является ли значение числом
    if ! [[ "$memory_percent" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        log "ERROR: Invalid memory percentage: $memory_percent"
        return 1
    fi

    # Получить детальную информацию
    local memory_usage
    memory_usage=$(docker stats --no-stream --format "{{.MemUsage}}" "$CONTAINER_NAME" 2>/dev/null)

    log "Memory usage: $memory_percent% ($memory_usage)"

    # Проверить превышение порога
    if (( $(echo "$memory_percent > $MEMORY_THRESHOLD" | bc -l) )); then
        send_alert "LiteLLM memory usage exceeded threshold ($MEMORY_THRESHOLD%)" "$memory_percent"

        # Дополнительная диагностика
        log "Container details:"
        docker inspect "$CONTAINER_NAME" --format '{{.HostConfig.Memory}}' | tee -a "$LOG_FILE"

        # Топ процессов в контейнере
        log "Top processes in container:"
        docker exec "$CONTAINER_NAME" ps aux 2>/dev/null | head -10 | tee -a "$LOG_FILE" || true

        return 2  # Код возврата для превышения порога
    fi

    return 0
}

# Функция проверки здоровья контейнера
check_health() {
    local health_status
    health_status=$(docker inspect "$CONTAINER_NAME" --format '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")

    if [[ "$health_status" != "healthy" ]]; then
        log "WARNING: Container health status is '$health_status'"
        return 1
    fi

    return 0
}

# Основная функция
main() {
    log "Starting LiteLLM memory monitoring check"

    # Проверить существование контейнера
    if ! docker ps --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
        log "ERROR: Container $CONTAINER_NAME is not running"
        exit 1
    fi

    # Проверить память
    local memory_check_result=0
    check_memory || memory_check_result=$?

    # Проверить здоровье
    local health_check_result=0
    check_health || health_check_result=$?

    # Итоговый статус
    if [[ $memory_check_result -eq 2 ]]; then
        log "CRITICAL: Memory threshold exceeded"
        exit 2
    elif [[ $memory_check_result -ne 0 || $health_check_result -ne 0 ]]; then
        log "WARNING: Some checks failed"
        exit 1
    else
        log "OK: All checks passed"
        exit 0
    fi
}

# Создать директорию для логов если не существует
mkdir -p "$(dirname "$LOG_FILE")"

# Запуск основной функции
main "$@"
