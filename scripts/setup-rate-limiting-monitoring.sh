#!/bin/bash

# ERNI-KI Rate Limiting Monitoring Setup
# Настройка автоматического мониторинга rate limiting
# Автор: Альтэон Шульц (Tech Lead)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# === Функции логирования ===
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $*"
}

# === Создание cron задачи ===
setup_cron_monitoring() {
    log "Настройка cron мониторинга..."
    
    local cron_entry="*/1 * * * * cd $PROJECT_ROOT && ./scripts/monitor-rate-limiting.sh monitor >/dev/null 2>&1"
    
    # Проверка существующей cron задачи
    if crontab -l 2>/dev/null | grep -q "monitor-rate-limiting.sh"; then
        log "Cron задача уже существует"
    else
        # Добавление новой cron задачи
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        success "Cron задача добавлена: мониторинг каждую минуту"
    fi
}

# === Создание systemd сервиса ===
setup_systemd_service() {
    log "Создание systemd сервиса..."
    
    local service_file="/etc/systemd/system/erni-ki-rate-monitor.service"
    local timer_file="/etc/systemd/system/erni-ki-rate-monitor.timer"
    
    # Создание сервиса
    sudo tee "$service_file" > /dev/null <<EOF
[Unit]
Description=ERNI-KI Rate Limiting Monitor
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=$USER
WorkingDirectory=$PROJECT_ROOT
ExecStart=$PROJECT_ROOT/scripts/monitor-rate-limiting.sh monitor
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Создание таймера
    sudo tee "$timer_file" > /dev/null <<EOF
[Unit]
Description=Run ERNI-KI Rate Limiting Monitor every minute
Requires=erni-ki-rate-monitor.service

[Timer]
OnCalendar=*:*:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Перезагрузка systemd и запуск
    sudo systemctl daemon-reload
    sudo systemctl enable erni-ki-rate-monitor.timer
    sudo systemctl start erni-ki-rate-monitor.timer
    
    success "Systemd сервис настроен и запущен"
}

# === Настройка логротации ===
setup_log_rotation() {
    log "Настройка ротации логов..."
    
    local logrotate_config="/etc/logrotate.d/erni-ki-rate-limiting"
    
    sudo tee "$logrotate_config" > /dev/null <<EOF
$PROJECT_ROOT/logs/rate-limiting-*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 $USER $USER
    postrotate
        # Отправка сигнала для обновления логов (если нужно)
    endscript
}
EOF

    success "Логротация настроена"
}

# === Создание dashboard скрипта ===
create_dashboard() {
    log "Создание dashboard скрипта..."
    
    cat > "$PROJECT_ROOT/scripts/rate-limiting-dashboard.sh" <<'EOF'
#!/bin/bash

# ERNI-KI Rate Limiting Dashboard
# Простой dashboard для мониторинга rate limiting

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="$PROJECT_ROOT/logs/rate-limiting-state.json"

clear
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                        ERNI-KI Rate Limiting Dashboard                      ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo

# Текущий статус
echo "📊 Текущий статус:"
if [[ -f "$STATE_FILE" ]]; then
    echo "   Последнее обновление: $(jq -r '.timestamp' "$STATE_FILE" 2>/dev/null || echo 'N/A')"
    echo "   Блокировок за минуту: $(jq -r '.total_blocks' "$STATE_FILE" 2>/dev/null || echo 'N/A')"
    echo "   Максимальное превышение: $(jq -r '.max_excess' "$STATE_FILE" 2>/dev/null || echo 'N/A')"
else
    echo "   ⚠️  Нет данных мониторинга"
fi

echo

# Статистика по зонам
echo "🎯 Статистика по зонам:"
if [[ -f "$STATE_FILE" ]] && jq -e '.zones | length > 0' "$STATE_FILE" >/dev/null 2>&1; then
    jq -r '.zones[] | "   \(.zone): \(.count) блокировок"' "$STATE_FILE" 2>/dev/null
else
    echo "   ✅ Нет блокировок"
fi

echo

# Топ IP адресов
echo "🌐 Топ IP адресов:"
if [[ -f "$STATE_FILE" ]] && jq -e '.top_ips | length > 0' "$STATE_FILE" >/dev/null 2>&1; then
    jq -r '.top_ips[] | "   \(.ip): \(.count) блокировок"' "$STATE_FILE" 2>/dev/null | head -5
else
    echo "   ✅ Нет проблемных IP"
fi

echo

# Последние алерты
echo "🚨 Последние алерты:"
local alert_file="$PROJECT_ROOT/logs/rate-limiting-alerts.log"
if [[ -f "$alert_file" ]]; then
    tail -5 "$alert_file" | grep -E "^\[.*\] \[.*\]" | while read -r line; do
        echo "   $line"
    done
else
    echo "   ✅ Нет алертов"
fi

echo
echo "Обновлено: $(date)"
echo "Для выхода нажмите Ctrl+C"
EOF

    chmod +x "$PROJECT_ROOT/scripts/rate-limiting-dashboard.sh"
    success "Dashboard создан: scripts/rate-limiting-dashboard.sh"
}

# === Настройка уведомлений ===
setup_notifications() {
    log "Настройка интеграции уведомлений..."
    
    # Создание конфигурационного файла для уведомлений
    cat > "$PROJECT_ROOT/conf/rate-limiting-notifications.conf" <<EOF
# ERNI-KI Rate Limiting Notifications Configuration

# Пороги алертов
ALERT_THRESHOLD=10
WARNING_THRESHOLD=5

# Email уведомления (если настроен sendmail)
EMAIL_ENABLED=false
EMAIL_TO="admin@example.com"

# Slack уведомления (если настроен webhook)
SLACK_ENABLED=false
SLACK_WEBHOOK_URL=""

# Discord уведомления (если настроен webhook)
DISCORD_ENABLED=false
DISCORD_WEBHOOK_URL=""

# Telegram уведомления (если настроен bot)
TELEGRAM_ENABLED=false
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

# Backrest интеграция
BACKREST_ENABLED=true
BACKREST_URL="http://localhost:9898"
EOF

    success "Конфигурация уведомлений создана"
}

# === Тестирование системы ===
test_monitoring() {
    log "Тестирование системы мониторинга..."
    
    # Запуск тестовой проверки
    if "$PROJECT_ROOT/scripts/monitor-rate-limiting.sh" monitor; then
        success "Мониторинг работает корректно"
    else
        error "Ошибка в работе мониторинга"
        return 1
    fi
    
    # Проверка создания файлов
    if [[ -f "$PROJECT_ROOT/logs/rate-limiting-monitor.log" ]]; then
        success "Лог файл создан"
    else
        error "Лог файл не создан"
    fi
    
    return 0
}

# === Основная функция ===
main() {
    log "Настройка системы мониторинга rate limiting для ERNI-KI"
    
    # Создание директорий
    mkdir -p "$PROJECT_ROOT/logs"
    mkdir -p "$PROJECT_ROOT/conf"
    
    # Выбор метода мониторинга
    case "${1:-cron}" in
        "cron")
            setup_cron_monitoring
            ;;
        "systemd")
            setup_systemd_service
            ;;
        "both")
            setup_cron_monitoring
            setup_systemd_service
            ;;
        *)
            error "Неизвестный метод: $1"
            echo "Доступные методы: cron, systemd, both"
            exit 1
            ;;
    esac
    
    # Общие настройки
    setup_log_rotation
    create_dashboard
    setup_notifications
    
    # Тестирование
    if test_monitoring; then
        success "Система мониторинга настроена успешно!"
        
        echo
        echo "📋 Что было настроено:"
        echo "  ✅ Мониторинг rate limiting каждую минуту"
        echo "  ✅ Автоматические алерты при превышении порогов"
        echo "  ✅ Ротация логов (30 дней)"
        echo "  ✅ Dashboard для просмотра статистики"
        echo "  ✅ Интеграция с Backrest для уведомлений"
        
        echo
        echo "🚀 Полезные команды:"
        echo "  ./scripts/monitor-rate-limiting.sh stats    # Показать статистику"
        echo "  ./scripts/rate-limiting-dashboard.sh        # Запустить dashboard"
        echo "  tail -f logs/rate-limiting-monitor.log      # Просмотр логов"
        
    else
        error "Ошибка при настройке системы мониторинга"
        exit 1
    fi
}

# Запуск
main "$@"
