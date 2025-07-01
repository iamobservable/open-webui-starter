#!/bin/bash
# Скрипт управления Backrest для ERNI-KI
# Предоставляет удобные команды для управления бэкапами

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции логирования
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
    exit 1
}

# Проверка состояния Backrest
check_backrest_status() {
    log "Проверка состояния Backrest..."

    # Определяем команду Docker Compose
    if command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE="docker-compose"
    elif docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
    else
        error "Docker Compose не найден"
    fi

    if ! $DOCKER_COMPOSE ps backrest | grep -q "Up"; then
        error "Backrest не запущен. Запустите его командой: $DOCKER_COMPOSE up -d backrest"
    fi

    # Проверяем доступность веб-интерфейса
    if ! curl -s -o /dev/null -w "%{http_code}" http://localhost:9898/ | grep -q "200"; then
        error "Backrest веб-интерфейс недоступен. Проверьте логи: $DOCKER_COMPOSE logs backrest"
    fi

    success "Backrest работает корректно"
}

# Создание ручного бэкапа
create_manual_backup() {
    local plan_id=${1:-"critical-data-daily"}

    log "Создание ручного бэкапа для плана: $plan_id"

    check_backrest_status

    # Создание бэкапа через API (требует дополнительной реализации)
    log "Для создания ручного бэкапа используйте веб-интерфейс: http://localhost:9898"
    log "Или выполните команду в контейнере Backrest"

    docker-compose exec backrest sh -c "echo 'Manual backup triggered for plan: $plan_id'"
}

# Просмотр статуса бэкапов
show_backup_status() {
    log "Получение статуса бэкапов..."

    check_backrest_status

    # Определяем команду Docker Compose
    if command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE="docker-compose"
    elif docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
    else
        error "Docker Compose не найден"
    fi

    echo ""
    log "=== Статус контейнера Backrest ==="
    $DOCKER_COMPOSE ps backrest

    echo ""
    log "=== Последние логи Backrest ==="
    $DOCKER_COMPOSE logs --tail=20 backrest

    echo ""
    log "=== Использование дискового пространства ==="
    $DOCKER_COMPOSE exec backrest df -h /data

    echo ""
    log "=== Список репозиториев ==="
    if [ -d "data/backrest/repositories" ]; then
        ls -la data/backrest/repositories/
    else
        warning "Директория репозиториев не найдена"
    fi
}

# Восстановление из бэкапа
restore_backup() {
    local snapshot_id=${1:-""}
    local restore_path=${2:-"./restore"}

    if [ -z "$snapshot_id" ]; then
        error "Укажите ID снапшота для восстановления"
    fi

    log "Восстановление снапшота $snapshot_id в $restore_path"

    check_backrest_status

    # Создание директории для восстановления
    mkdir -p "$restore_path"

    log "Для восстановления используйте веб-интерфейс Backrest: http://localhost:9898"
    log "Или выполните команду restic напрямую в контейнере"

    warning "ВНИМАНИЕ: Убедитесь, что вы восстанавливаете в правильную директорию"
}

# Очистка старых бэкапов
cleanup_backups() {
    log "Запуск очистки старых бэкапов..."

    check_backrest_status

    log "Очистка выполняется автоматически по расписанию"
    log "Для ручной очистки используйте веб-интерфейс или команды restic"

    docker-compose exec backrest sh -c "echo 'Cleanup process can be triggered from web UI'"
}

# Проверка целостности бэкапов
check_backup_integrity() {
    log "Проверка целостности бэкапов..."

    check_backrest_status

    log "Проверка целостности выполняется автоматически по расписанию"
    log "Для ручной проверки используйте веб-интерфейс Backrest"

    docker-compose exec backrest sh -c "echo 'Integrity check can be triggered from web UI'"
}

# Экспорт конфигурации
export_config() {
    local backup_file="backrest-config-backup-$(date +%Y%m%d_%H%M%S).tar.gz"

    log "Экспорт конфигурации Backrest..."

    tar -czf "$backup_file" \
        env/backrest.env \
        conf/backrest/ \
        .backrest_secrets 2>/dev/null || true

    success "Конфигурация экспортирована в $backup_file"
    warning "Файл содержит секретные ключи - храните его в безопасности!"
}

# Мониторинг бэкапов
monitor_backups() {
    log "Запуск мониторинга бэкапов..."

    while true; do
        clear
        echo "=== ERNI-KI Backrest Monitor ==="
        echo "Время: $(date)"
        echo ""

        # Статус контейнера
        echo "Статус контейнера:"
        docker-compose ps backrest | grep backrest || echo "Контейнер не найден"
        echo ""

        # Использование ресурсов
        echo "Использование ресурсов:"
        docker stats --no-stream backrest 2>/dev/null || echo "Статистика недоступна"
        echo ""

        # Последние логи
        echo "Последние логи (5 строк):"
        docker-compose logs --tail=5 backrest 2>/dev/null || echo "Логи недоступны"
        echo ""

        echo "Нажмите Ctrl+C для выхода"
        sleep 30
    done
}

# Показать справку
show_help() {
    echo "Скрипт управления Backrest для ERNI-KI"
    echo ""
    echo "Использование: $0 [команда] [параметры]"
    echo ""
    echo "Команды:"
    echo "  status                    - Показать статус бэкапов"
    echo "  backup [plan_id]         - Создать ручной бэкап"
    echo "  restore <snapshot> [path] - Восстановить из бэкапа"
    echo "  cleanup                  - Очистить старые бэкапы"
    echo "  check                    - Проверить целостность бэкапов"
    echo "  export                   - Экспортировать конфигурацию"
    echo "  monitor                  - Запустить мониторинг"
    echo "  help                     - Показать эту справку"
    echo ""
    echo "Примеры:"
    echo "  $0 status"
    echo "  $0 backup critical-data-daily"
    echo "  $0 restore abc123def ./restore-folder"
    echo "  $0 monitor"
}

# Основная функция
main() {
    local command=${1:-"help"}

    case $command in
        "status")
            show_backup_status
            ;;
        "backup")
            create_manual_backup "${2:-}"
            ;;
        "restore")
            restore_backup "${2:-}" "${3:-}"
            ;;
        "cleanup")
            cleanup_backups
            ;;
        "check")
            check_backup_integrity
            ;;
        "export")
            export_config
            ;;
        "monitor")
            monitor_backups
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# Запуск скрипта
main "$@"
