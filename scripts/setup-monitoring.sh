#!/bin/bash

# 📊 ERNI-KI Monitoring Setup Script
# Настройка системы мониторинга и логирования
# Создано: Альтэон Шульц, Tech Lead

set -euo pipefail

# === КОНФИГУРАЦИЯ ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CRON_FILE="/tmp/erni-ki-monitoring-cron"

# === ЦВЕТА ДЛЯ ВЫВОДА ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# === ФУНКЦИИ ===
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# === СОЗДАНИЕ ДИРЕКТОРИЙ ===
setup_directories() {
    log_info "Создание директорий для мониторинга..."
    
    mkdir -p "$PROJECT_DIR/.config-backup/monitoring"
    mkdir -p "$PROJECT_DIR/.config-backup/logs"
    mkdir -p "$PROJECT_DIR/scripts"
    
    log_success "Директории созданы"
}

# === НАСТРОЙКА CRON ЗАДАЧ ===
setup_cron() {
    log_info "Настройка cron задач для автоматического мониторинга..."
    
    # Создание cron файла
    cat > "$CRON_FILE" << EOF
# ERNI-KI System Monitoring
# Автоматический мониторинг состояния системы

# Проверка каждый час
0 * * * * cd $PROJECT_DIR && ./scripts/health-monitor.sh >> .config-backup/monitoring/cron.log 2>&1

# Ежедневная очистка старых логов (старше 7 дней)
0 2 * * * find $PROJECT_DIR/.config-backup/monitoring -name "health-report-*.md" -mtime +7 -delete

# Еженедельный полный отчет (воскресенье в 3:00)
0 3 * * 0 cd $PROJECT_DIR && ./scripts/health-monitor.sh > .config-backup/monitoring/weekly-report-\$(date +\%Y\%m\%d).md 2>&1
EOF
    
    # Установка cron задач
    if crontab -l > /dev/null 2>&1; then
        # Добавление к существующему crontab
        (crontab -l; cat "$CRON_FILE") | crontab -
    else
        # Создание нового crontab
        crontab "$CRON_FILE"
    fi
    
    rm -f "$CRON_FILE"
    
    log_success "Cron задачи настроены:"
    log_info "  - Ежечасная проверка системы"
    log_info "  - Ежедневная очистка логов"
    log_info "  - Еженедельный полный отчет"
}

# === НАСТРОЙКА УРОВНЕЙ ЛОГИРОВАНИЯ ===
setup_logging_levels() {
    log_info "Настройка оптимальных уровней логирования..."
    
    cd "$PROJECT_DIR"
    
    # Создание резервной копии конфигураций
    local backup_dir=".config-backup/logging-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Резервное копирование важных конфигураций
    if [[ -f "env/openwebui.env" ]]; then
        cp "env/openwebui.env" "$backup_dir/"
    fi
    
    if [[ -f "env/ollama.env" ]]; then
        cp "env/ollama.env" "$backup_dir/"
    fi
    
    log_success "Резервные копии созданы в $backup_dir"
    
    # Настройка логирования для OpenWebUI (уменьшение шума)
    if grep -q "LOG_LEVEL" env/openwebui.env; then
        log_info "LOG_LEVEL уже настроен в OpenWebUI"
    else
        echo "" >> env/openwebui.env
        echo "# === НАСТРОЙКИ ЛОГИРОВАНИЯ ===" >> env/openwebui.env
        echo "# Уровень логирования (INFO для продакшена, DEBUG для отладки)" >> env/openwebui.env
        echo "LOG_LEVEL=INFO" >> env/openwebui.env
        log_success "Добавлен LOG_LEVEL=INFO в OpenWebUI"
    fi
    
    # Настройка логирования для Ollama
    if grep -q "OLLAMA_LOG_LEVEL" env/ollama.env; then
        log_info "OLLAMA_LOG_LEVEL уже настроен"
    else
        echo "" >> env/ollama.env
        echo "# === НАСТРОЙКИ ЛОГИРОВАНИЯ ===" >> env/ollama.env
        echo "# Уровень логирования Ollama (INFO для продакшена)" >> env/ollama.env
        echo "OLLAMA_LOG_LEVEL=INFO" >> env/ollama.env
        log_success "Добавлен OLLAMA_LOG_LEVEL=INFO в Ollama"
    fi
}

# === СОЗДАНИЕ АЛЕРТОВ ===
setup_alerts() {
    log_info "Создание системы алертов..."
    
    # Создание скрипта для критических алертов
    cat > "$PROJECT_DIR/scripts/critical-alert.sh" << 'EOF'
#!/bin/bash
# Скрипт для отправки критических алертов

ALERT_TYPE="$1"
MESSAGE="$2"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Логирование алерта
echo "[$TIMESTAMP] CRITICAL ALERT: $ALERT_TYPE - $MESSAGE" >> .config-backup/monitoring/critical-alerts.log

# Здесь можно добавить отправку уведомлений:
# - Email
# - Slack/Discord webhook
# - Telegram bot
# - SMS

echo "CRITICAL ALERT: $ALERT_TYPE"
echo "Message: $MESSAGE"
echo "Time: $TIMESTAMP"
EOF
    
    chmod +x "$PROJECT_DIR/scripts/critical-alert.sh"
    
    log_success "Система алертов создана"
}

# === ТЕСТИРОВАНИЕ МОНИТОРИНГА ===
test_monitoring() {
    log_info "Тестирование системы мониторинга..."
    
    cd "$PROJECT_DIR"
    
    # Запуск тестовой проверки
    if ./scripts/health-monitor.sh; then
        log_success "Тест мониторинга прошел успешно"
    else
        log_warning "Тест мониторинга выявил проблемы (это нормально для первого запуска)"
    fi
    
    # Проверка создания отчета
    local latest_report
    latest_report=$(find .config-backup/monitoring -name "health-report-*.md" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2- || echo "")
    
    if [[ -n "$latest_report" && -f "$latest_report" ]]; then
        log_success "Отчет создан: $latest_report"
        log_info "Размер отчета: $(wc -l < "$latest_report") строк"
    else
        log_error "Отчет не создан"
        return 1
    fi
}

# === ГЛАВНАЯ ФУНКЦИЯ ===
main() {
    log_info "🔧 Настройка системы мониторинга ERNI-KI"
    echo ""
    
    setup_directories
    setup_logging_levels
    setup_cron
    setup_alerts
    test_monitoring
    
    echo ""
    log_success "🎉 НАСТРОЙКА МОНИТОРИНГА ЗАВЕРШЕНА!"
    echo ""
    log_info "📋 Что настроено:"
    log_info "  ✅ Автоматические проверки каждый час"
    log_info "  ✅ Еженедельные отчеты"
    log_info "  ✅ Автоматическая очистка логов"
    log_info "  ✅ Система алертов"
    log_info "  ✅ Оптимизированные уровни логирования"
    echo ""
    log_info "📁 Файлы мониторинга:"
    log_info "  - Отчеты: .config-backup/monitoring/"
    log_info "  - Скрипты: scripts/"
    log_info "  - Алерты: .config-backup/monitoring/critical-alerts.log"
    echo ""
    log_info "🔧 Управление:"
    log_info "  - Ручная проверка: ./scripts/health-monitor.sh"
    log_info "  - Просмотр cron: crontab -l | grep erni-ki"
    log_info "  - Логи cron: .config-backup/monitoring/cron.log"
    echo ""
    log_success "Система готова к автоматическому мониторингу!"
}

# === ЗАПУСК ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
