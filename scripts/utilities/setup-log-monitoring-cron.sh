#!/bin/bash

# ============================================================================
# SETUP LOG MONITORING CRON JOB
# Настройка автоматического мониторинга логов ERNI-KI
# Создан: 2025-09-18
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_MONITORING_SCRIPT="$SCRIPT_DIR/log-monitoring.sh"

# Цвета для вывода
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Функция настройки cron задачи
setup_cron() {
    log "Настройка cron задачи для мониторинга логов..."

    # Создание временного файла с новой cron задачей
    local temp_cron=$(mktemp)

    # Получение текущих cron задач (исключая наш мониторинг)
    crontab -l 2>/dev/null | grep -v "log-monitoring.sh" > "$temp_cron" || true

    # Добавление новой задачи (каждые 30 минут)
    cat >> "$temp_cron" << EOF

# ERNI-KI Log Monitoring (добавлено $(date '+%Y-%m-%d'))
# Запуск каждые 30 минут для мониторинга размеров логов
*/30 * * * * cd "$PROJECT_ROOT" && "$LOG_MONITORING_SCRIPT" >> "$PROJECT_ROOT/logs/log-monitoring-cron.log" 2>&1

# ERNI-KI Log Monitoring - ежедневная очистка в 03:00
0 3 * * * cd "$PROJECT_ROOT" && "$LOG_MONITORING_SCRIPT" --cleanup >> "$PROJECT_ROOT/logs/log-monitoring-cron.log" 2>&1
EOF

    # Установка новой crontab
    crontab "$temp_cron"
    rm -f "$temp_cron"

    success "Cron задачи настроены:"
    echo "  - Мониторинг каждые 30 минут"
    echo "  - Ежедневная очистка в 03:00"
}

# Функция проверки cron задач
check_cron() {
    log "Проверка текущих cron задач..."

    local cron_jobs=$(crontab -l 2>/dev/null | grep -c "log-monitoring.sh" || echo "0")

    if [[ "$cron_jobs" -gt 0 ]]; then
        success "Найдено $cron_jobs cron задач для мониторинга логов"
        echo
        echo "Текущие задачи:"
        crontab -l | grep "log-monitoring.sh" || true
    else
        warn "Cron задачи для мониторинга логов не найдены"
        return 1
    fi
}

# Функция удаления cron задач
remove_cron() {
    log "Удаление cron задач мониторинга логов..."

    local temp_cron=$(mktemp)
    crontab -l 2>/dev/null | grep -v "log-monitoring.sh" > "$temp_cron" || true
    crontab "$temp_cron"
    rm -f "$temp_cron"

    success "Cron задачи удалены"
}

# Функция создания systemd timer (альтернатива cron)
setup_systemd_timer() {
    log "Настройка systemd timer для мониторинга логов..."

    # Создание service файла
    sudo tee /etc/systemd/system/erni-ki-log-monitoring.service > /dev/null << EOF
[Unit]
Description=ERNI-KI Log Monitoring
After=docker.service

[Service]
Type=oneshot
User=$USER
WorkingDirectory=$PROJECT_ROOT
ExecStart=$LOG_MONITORING_SCRIPT
StandardOutput=append:$PROJECT_ROOT/logs/log-monitoring-systemd.log
StandardError=append:$PROJECT_ROOT/logs/log-monitoring-systemd.log
EOF

    # Создание timer файла
    sudo tee /etc/systemd/system/erni-ki-log-monitoring.timer > /dev/null << EOF
[Unit]
Description=Run ERNI-KI Log Monitoring every 30 minutes
Requires=erni-ki-log-monitoring.service

[Timer]
OnCalendar=*:0/30
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Перезагрузка systemd и запуск timer
    sudo systemctl daemon-reload
    sudo systemctl enable erni-ki-log-monitoring.timer
    sudo systemctl start erni-ki-log-monitoring.timer

    success "Systemd timer настроен и запущен"
}

# Основная функция
main() {
    echo "============================================================================"
    echo "🔧 ERNI-KI LOG MONITORING CRON SETUP"
    echo "============================================================================"

    case "${1:-setup}" in
        "setup"|"install")
            setup_cron
            ;;
        "check"|"status")
            check_cron
            ;;
        "remove"|"uninstall")
            remove_cron
            ;;
        "systemd")
            setup_systemd_timer
            ;;
        *)
            echo "Использование: $0 [setup|check|remove|systemd]"
            echo
            echo "Команды:"
            echo "  setup    - Настроить cron задачи (по умолчанию)"
            echo "  check    - Проверить текущие cron задачи"
            echo "  remove   - Удалить cron задачи"
            echo "  systemd  - Настроить systemd timer (альтернатива cron)"
            exit 1
            ;;
    esac

    echo "============================================================================"
}

# Запуск скрипта
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
