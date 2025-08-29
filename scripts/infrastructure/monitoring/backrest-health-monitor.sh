#!/bin/bash

# ERNI-KI Backrest Health Monitor
# Автоматизированный мониторинг состояния системы резервного копирования
# Версия: 1.0
# Дата: 2025-08-25

set -euo pipefail

# === Конфигурация ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="$PROJECT_ROOT/logs/backrest-health.log"
ALERT_LOG="$PROJECT_ROOT/logs/backrest-alerts.log"
BACKREST_API="http://localhost:9898"

# Пороговые значения
MAX_BACKUP_AGE_HOURS=25  # Максимальный возраст последнего бекапа (часы)
MIN_SNAPSHOTS_COUNT=3    # Минимальное количество снапшотов
MAX_REPO_SIZE_GB=5       # Максимальный размер репозитория (GB)
CRITICAL_DISK_USAGE=90   # Критический уровень использования диска (%)

# === Функции логирования ===
log() {
    echo "[$(date -Iseconds)] INFO: $*" | tee -a "$LOG_FILE"
}

warning() {
    echo "[$(date -Iseconds)] WARNING: $*" | tee -a "$LOG_FILE" "$ALERT_LOG"
}

error() {
    echo "[$(date -Iseconds)] ERROR: $*" | tee -a "$LOG_FILE" "$ALERT_LOG"
}

success() {
    echo "[$(date -Iseconds)] SUCCESS: $*" | tee -a "$LOG_FILE"
}

# === Создание директорий ===
mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$ALERT_LOG")"

# === Проверка доступности Backrest ===
check_backrest_availability() {
    log "Проверка доступности Backrest API..."

    if curl -s -f "$BACKREST_API/" >/dev/null 2>&1; then
        success "Backrest API доступен"
        return 0
    else
        error "Backrest API недоступен"
        return 1
    fi
}

# === Проверка статуса контейнера ===
check_container_status() {
    log "Проверка статуса Docker контейнера..."

    local container_status
    container_status=$(timeout 10 docker ps --filter "name=backrest" --format "{{.Status}}" 2>/dev/null || echo "not found")

    if [[ "$container_status" == *"healthy"* ]] || [[ "$container_status" == *"Up"* ]]; then
        success "Контейнер Backrest работает корректно: $container_status"
        return 0
    else
        error "Проблема с контейнером Backrest: $container_status"
        return 1
    fi
}

# === Проверка последнего бекапа ===
check_last_backup() {
    log "Проверка времени последнего бекапа..."

    local snapshots_count
    snapshots_count=$(timeout 30 docker exec erni-ki-backrest-1 restic -r /backup-sources/.config-backup/repositories/erni-ki-local --password-file /config/repo-password.txt snapshots --json 2>/dev/null | jq '. | length' 2>/dev/null || echo "0")

    if [[ "$snapshots_count" -lt "$MIN_SNAPSHOTS_COUNT" ]]; then
        warning "Недостаточно снапшотов: $snapshots_count (минимум: $MIN_SNAPSHOTS_COUNT)"
        return 1
    fi

    local last_backup_time
    last_backup_time=$(timeout 30 docker exec erni-ki-backrest-1 restic -r /backup-sources/.config-backup/repositories/erni-ki-local --password-file /config/repo-password.txt snapshots --json 2>/dev/null | jq -r '.[-1].time' 2>/dev/null || echo "")

    if [[ -z "$last_backup_time" ]]; then
        error "Не удалось получить время последнего бекапа"
        return 1
    fi

    local backup_age_seconds
    backup_age_seconds=$(( $(date +%s) - $(date -d "$last_backup_time" +%s) ))
    local backup_age_hours=$(( backup_age_seconds / 3600 ))

    if [[ "$backup_age_hours" -gt "$MAX_BACKUP_AGE_HOURS" ]]; then
        warning "Последний бекап слишком старый: $backup_age_hours часов назад (максимум: $MAX_BACKUP_AGE_HOURS)"
        return 1
    else
        success "Последний бекап: $backup_age_hours часов назад (снапшотов: $snapshots_count)"
        return 0
    fi
}

# === Проверка размера репозитория ===
check_repository_size() {
    log "Проверка размера репозитория..."

    local repo_size_mb
    repo_size_mb=$(du -sm "$PROJECT_ROOT/.config-backup/repositories/erni-ki-local" 2>/dev/null | cut -f1 || echo "0")
    local repo_size_gb=$(( repo_size_mb / 1024 ))

    if [[ "$repo_size_gb" -gt "$MAX_REPO_SIZE_GB" ]]; then
        warning "Размер репозитория превышает лимит: ${repo_size_gb}GB (максимум: ${MAX_REPO_SIZE_GB}GB)"
        return 1
    else
        success "Размер репозитория: ${repo_size_mb}MB (${repo_size_gb}GB)"
        return 0
    fi
}

# === Проверка использования диска ===
check_disk_usage() {
    log "Проверка использования диска..."

    local disk_usage
    disk_usage=$(df "$PROJECT_ROOT" | awk 'NR==2 {print $5}' | sed 's/%//')

    if [[ "$disk_usage" -gt "$CRITICAL_DISK_USAGE" ]]; then
        error "Критический уровень использования диска: ${disk_usage}% (максимум: ${CRITICAL_DISK_USAGE}%)"
        return 1
    else
        success "Использование диска: ${disk_usage}%"
        return 0
    fi
}

# === Проверка логов на ошибки ===
check_backrest_logs() {
    log "Проверка логов Backrest на ошибки..."

    local error_count
    error_count=$(docker logs --since 24h erni-ki-backrest-1 2>&1 | grep -i "error\|failed\|panic" | wc -l || echo "0")

    if [[ "$error_count" -gt 0 ]]; then
        warning "Найдено $error_count ошибок в логах за последние 24 часа"
        return 1
    else
        success "Ошибок в логах не найдено"
        return 0
    fi
}

# === Отправка уведомлений ===
send_notification() {
    local status="$1"
    local message="$2"

    # Webhook уведомление
    if [[ -x "$PROJECT_ROOT/scripts/backup/backrest-webhook.sh" ]]; then
        "$PROJECT_ROOT/scripts/backup/backrest-webhook.sh" "[$status] $message"
    fi

    # Системный журнал
    echo "Backrest Health Monitor [$status]: $message" | logger -t "erni-ki-backrest-monitor"
}

# === Основная функция мониторинга ===
main() {
    log "=== Запуск мониторинга Backrest ==="

    local checks_passed=0
    local checks_total=6
    local critical_issues=0

    # Выполнение проверок
    check_backrest_availability && ((checks_passed++)) || ((critical_issues++))
    check_container_status && ((checks_passed++)) || ((critical_issues++))
    check_last_backup && ((checks_passed++)) || true
    check_repository_size && ((checks_passed++)) || true
    check_disk_usage && ((checks_passed++)) || ((critical_issues++))
    check_backrest_logs && ((checks_passed++)) || true

    # Итоговый отчет
    log "=== Результаты мониторинга ==="
    log "Проверок пройдено: $checks_passed/$checks_total"
    log "Критических проблем: $critical_issues"

    if [[ "$critical_issues" -eq 0 ]]; then
        if [[ "$checks_passed" -eq "$checks_total" ]]; then
            success "Все проверки пройдены успешно"
            send_notification "SUCCESS" "Все проверки Backrest пройдены успешно ($checks_passed/$checks_total)"
            return 0
        else
            warning "Есть предупреждения, но критических проблем нет"
            send_notification "WARNING" "Backrest работает с предупреждениями ($checks_passed/$checks_total проверок пройдено)"
            return 1
        fi
    else
        error "Обнаружены критические проблемы"
        send_notification "CRITICAL" "Обнаружены критические проблемы с Backrest ($critical_issues критических, $checks_passed/$checks_total проверок пройдено)"
        return 2
    fi
}

# === Запуск ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
