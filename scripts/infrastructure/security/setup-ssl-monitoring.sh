#!/bin/bash

# Настройка автоматического мониторинга SSL сертификатов для ERNI-KI
# Создает systemd timer или cron job для регулярной проверки

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции для логирования
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Конфигурация
PROJECT_DIR="$(pwd)"
MONITOR_SCRIPT="$PROJECT_DIR/scripts/infrastructure/security/monitor-certificates.sh"
SERVICE_NAME="erni-ki-ssl-monitor"
TIMER_NAME="erni-ki-ssl-monitor"

# Проверка прав доступа
check_permissions() {
    log "Проверка прав доступа..."

    if [ "$EUID" -eq 0 ]; then
        log "Запуск от root, будет создан системный timer"
        SYSTEMD_DIR="/etc/systemd/system"
    else
        log "Запуск от пользователя, будет создан пользовательский timer"
        SYSTEMD_DIR="$HOME/.config/systemd/user"
        mkdir -p "$SYSTEMD_DIR"
    fi
}

# Создание systemd service
create_systemd_service() {
    log "Создание systemd service..."

    local service_file="$SYSTEMD_DIR/$SERVICE_NAME.service"

    if [ "$EUID" -eq 0 ]; then
        # Системный service с зависимостью от Docker
        cat > "$service_file" << EOF
[Unit]
Description=ERNI-KI SSL Certificate Monitor
After=network.target docker.service
Requires=docker.service

[Service]
Type=oneshot
User=$(whoami)
Group=$(id -gn)
WorkingDirectory=$PROJECT_DIR
Environment=PATH=/usr/local/bin:/usr/bin:/bin
Environment=HOME=$HOME
ExecStart=$MONITOR_SCRIPT check
StandardOutput=journal
StandardError=journal
TimeoutSec=300

[Install]
WantedBy=multi-user.target
EOF
    else
        # Пользовательский service без зависимости от Docker
        cat > "$service_file" << EOF
[Unit]
Description=ERNI-KI SSL Certificate Monitor
After=network.target

[Service]
Type=oneshot
WorkingDirectory=$PROJECT_DIR
Environment=PATH=/usr/local/bin:/usr/bin:/bin
Environment=HOME=$HOME
ExecStart=$MONITOR_SCRIPT check
StandardOutput=journal
StandardError=journal
TimeoutSec=300

[Install]
WantedBy=default.target
EOF
    fi

    success "Systemd service создан: $service_file"
}

# Создание systemd timer
create_systemd_timer() {
    log "Создание systemd timer..."

    local timer_file="$SYSTEMD_DIR/$TIMER_NAME.timer"

    cat > "$timer_file" << EOF
[Unit]
Description=ERNI-KI SSL Certificate Monitor Timer
Requires=$SERVICE_NAME.service

[Timer]
# Запуск каждый день в 02:00
OnCalendar=daily
# Запуск через 5 минут после загрузки системы
OnBootSec=5min
# Случайная задержка до 30 минут для распределения нагрузки
RandomizedDelaySec=30min
# Постоянный timer
Persistent=true

[Install]
WantedBy=timers.target
EOF

    success "Systemd timer создан: $timer_file"
}

# Настройка systemd мониторинга
setup_systemd_monitoring() {
    log "Настройка systemd мониторинга..."

    check_permissions
    create_systemd_service
    create_systemd_timer

    # Перезагрузка systemd
    if [ "$EUID" -eq 0 ]; then
        systemctl daemon-reload
        systemctl enable "$TIMER_NAME.timer"
        systemctl start "$TIMER_NAME.timer"

        log "Проверка статуса timer:"
        systemctl status "$TIMER_NAME.timer" --no-pager || true
    else
        systemctl --user daemon-reload
        systemctl --user enable "$TIMER_NAME.timer"
        systemctl --user start "$TIMER_NAME.timer"

        log "Проверка статуса timer:"
        systemctl --user status "$TIMER_NAME.timer" --no-pager || true
    fi

    success "Systemd мониторинг настроен"
}

# Создание cron job (альтернатива)
setup_cron_monitoring() {
    log "Настройка cron мониторинга..."

    # Проверка существующих cron jobs
    if crontab -l 2>/dev/null | grep -q "monitor-certificates.sh"; then
        warning "Cron job уже существует"
        return 0
    fi

    # Создание нового cron job
    local cron_entry="0 2 * * * cd $PROJECT_DIR && $MONITOR_SCRIPT check >/dev/null 2>&1"

    # Добавление к существующему crontab
    (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -

    success "Cron job создан: $cron_entry"

    # Показать текущий crontab
    log "Текущие cron jobs:"
    crontab -l | grep -E "(monitor-certificates|acme)" || echo "Нет связанных cron jobs"
}

# Создание скрипта для ручного запуска
create_manual_script() {
    log "Создание скрипта для ручного запуска..."

    local manual_script="$PROJECT_DIR/scripts/ssl/check-ssl-now.sh"

    cat > "$manual_script" << 'EOF'
#!/bin/bash
# Ручная проверка SSL сертификатов ERNI-KI

cd "$(dirname "$0")/../.."
./scripts/infrastructure/security/monitor-certificates.sh check
EOF

    chmod +x "$manual_script"
    success "Скрипт для ручного запуска создан: $manual_script"
}

# Создание конфигурационного файла
create_config_file() {
    log "Создание конфигурационного файла..."

    local config_file="$PROJECT_DIR/conf/ssl/monitoring.conf"
    mkdir -p "$(dirname "$config_file")"

    cat > "$config_file" << EOF
# ERNI-KI SSL Monitoring Configuration
# Конфигурация мониторинга SSL сертификатов

# Домен для мониторинга
DOMAIN=ki.erni-gruppe.ch

# Пороги предупреждений (дни)
DAYS_WARNING=30
DAYS_CRITICAL=7

# Webhook URL для уведомлений (опционально)
# SSL_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL

# Email для уведомлений (опционально)
# SSL_NOTIFICATION_EMAIL=admin@erni-ki.local

# Логирование
LOG_LEVEL=INFO
LOG_RETENTION_DAYS=30

# Автоматическое обновление
AUTO_RENEW_ENABLED=true
AUTO_RENEW_DAYS_BEFORE=7

# Cloudflare API (для автоматического обновления)
# CF_Token=your_cloudflare_api_token_here
# CF_Email=your_cloudflare_email@example.com
# CF_Key=your_cloudflare_global_api_key_here
EOF

    success "Конфигурационный файл создан: $config_file"
}

# Тестирование мониторинга
test_monitoring() {
    log "Тестирование мониторинга..."

    if [ -x "$MONITOR_SCRIPT" ]; then
        log "Запуск тестовой проверки..."
        "$MONITOR_SCRIPT" check
        success "Тестовая проверка завершена"
    else
        error "Скрипт мониторинга не найден или не исполняемый: $MONITOR_SCRIPT"
    fi
}

# Показать инструкции по использованию
show_usage_instructions() {
    echo ""
    log "=== ИНСТРУКЦИИ ПО ИСПОЛЬЗОВАНИЮ ==="
    echo ""

    log "Команды для управления мониторингом:"
    echo "• Ручная проверка: ./scripts/infrastructure/security/monitor-certificates.sh check"
    echo "• Принудительное обновление: ./scripts/infrastructure/security/monitor-certificates.sh renew"
    echo "• Генерация отчета: ./scripts/infrastructure/security/monitor-certificates.sh report"
    echo "• Тест HTTPS: ./scripts/infrastructure/security/monitor-certificates.sh test"
    echo ""

    if command -v systemctl >/dev/null 2>&1; then
        log "Команды systemd:"
        if [ "$EUID" -eq 0 ]; then
            echo "• Статус timer: systemctl status $TIMER_NAME.timer"
            echo "• Остановка timer: systemctl stop $TIMER_NAME.timer"
            echo "• Запуск timer: systemctl start $TIMER_NAME.timer"
            echo "• Логи: journalctl -u $SERVICE_NAME.service"
        else
            echo "• Статус timer: systemctl --user status $TIMER_NAME.timer"
            echo "• Остановка timer: systemctl --user stop $TIMER_NAME.timer"
            echo "• Запуск timer: systemctl --user start $TIMER_NAME.timer"
            echo "• Логи: journalctl --user -u $SERVICE_NAME.service"
        fi
    fi
    echo ""

    log "Файлы конфигурации:"
    echo "• Конфигурация мониторинга: conf/ssl/monitoring.conf"
    echo "• Логи мониторинга: logs/ssl-monitor.log"
    echo "• Отчеты: logs/ssl-report-*.txt"
    echo ""

    log "Настройка уведомлений:"
    echo "• Отредактируйте conf/ssl/monitoring.conf"
    echo "• Добавьте SSL_WEBHOOK_URL для Slack/Discord уведомлений"
    echo "• Настройте CF_Token для автоматического обновления"
}

# Основная функция
main() {
    local method="${1:-systemd}"

    echo -e "${BLUE}"
    echo "=============================================="
    echo "  ERNI-KI SSL Monitoring Setup"
    echo "  Method: $method"
    echo "=============================================="
    echo -e "${NC}"

    # Проверка, что мы в корне проекта
    if [ ! -f "compose.yml" ] && [ ! -f "compose.yml.example" ]; then
        error "Скрипт должен запускаться из корня проекта ERNI-KI"
    fi

    # Проверка существования скрипта мониторинга
    if [ ! -f "$MONITOR_SCRIPT" ]; then
        error "Скрипт мониторинга не найден: $MONITOR_SCRIPT"
    fi

    case "$method" in
        "systemd")
            if command -v systemctl >/dev/null 2>&1; then
                setup_systemd_monitoring
            else
                warning "systemd не найден, переключение на cron"
                setup_cron_monitoring
            fi
            ;;
        "cron")
            setup_cron_monitoring
            ;;
        "manual")
            log "Настройка только ручного мониторинга"
            ;;
        *)
            echo "Использование: $0 [systemd|cron|manual]"
            echo "  systemd - Использовать systemd timer (рекомендуется)"
            echo "  cron    - Использовать cron job"
            echo "  manual  - Только ручной запуск"
            exit 1
            ;;
    esac

    create_manual_script
    create_config_file
    test_monitoring
    show_usage_instructions

    success "Настройка SSL мониторинга завершена!"
}

# Запуск скрипта
main "$@"
