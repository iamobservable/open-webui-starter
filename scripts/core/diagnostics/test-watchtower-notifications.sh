#!/bin/bash

# ===== СКРИПТ ТЕСТИРОВАНИЯ УВЕДОМЛЕНИЙ WATCHTOWER =====
# Этот скрипт помогает протестировать настройки уведомлений Watchtower

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция логирования
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Проверка зависимостей
check_dependencies() {
    log "Проверка зависимостей..."

    if ! command -v docker &> /dev/null; then
        error "Docker не установлен"
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose не установлен"
        exit 1
    fi

    success "Все зависимости установлены"
}

# Проверка конфигурации
check_config() {
    log "Проверка конфигурации Watchtower..."

    if [[ ! -f "env/watchtower.env" ]]; then
        error "Файл env/watchtower.env не найден"
        exit 1
    fi

    # Проверка наличия URL уведомлений
    if grep -q "^WATCHTOWER_NOTIFICATION_URL=" env/watchtower.env; then
        success "URL уведомлений настроен"
    else
        warning "URL уведомлений не настроен в env/watchtower.env"
        echo "Добавьте строку: WATCHTOWER_NOTIFICATION_URL=\"your_notification_url\""
        return 1
    fi

    # Проверка включения отчетов
    if grep -q "^WATCHTOWER_NOTIFICATION_REPORT=true" env/watchtower.env; then
        success "Отчеты уведомлений включены"
    else
        warning "Отчеты уведомлений отключены"
    fi
}

# Тестирование уведомлений
test_notifications() {
    log "Запуск тестирования уведомлений..."

    # Создаем временный контейнер для тестирования
    local test_image="hello-world:latest"
    local test_container="watchtower-test-$(date +%s)"

    log "Создание тестового контейнера: $test_container"
    docker run -d --name "$test_container" --label="com.centurylinklabs.watchtower.enable=true" "$test_image" || true

    # Запуск Watchtower в режиме однократного выполнения
    log "Запуск Watchtower для тестирования уведомлений..."
    docker run --rm \
        -v /var/run/docker.sock:/var/run/docker.sock \
        --env-file env/watchtower.env \
        -e WATCHTOWER_RUN_ONCE=true \
        -e WATCHTOWER_DEBUG=true \
        -e WATCHTOWER_NOTIFICATION_REPORT=true \
        containrrr/watchtower \
        --run-once \
        --debug \
        --cleanup \
        "$test_container" || true

    # Очистка
    log "Очистка тестового контейнера..."
    docker rm -f "$test_container" 2>/dev/null || true

    success "Тестирование завершено. Проверьте получение уведомления."
}

# Проверка статуса Watchtower
check_watchtower_status() {
    log "Проверка статуса Watchtower..."

    if docker-compose ps watchtower | grep -q "Up.*healthy"; then
        success "Watchtower запущен и здоров"
    elif docker-compose ps watchtower | grep -q "Up"; then
        warning "Watchtower запущен, но статус здоровья неизвестен"
    else
        error "Watchtower не запущен"
        return 1
    fi

    # Показать последние логи
    log "Последние логи Watchtower:"
    docker-compose logs --tail=10 watchtower
}

# Проверка конфигурации уведомлений
validate_notification_config() {
    log "Валидация конфигурации уведомлений..."

    local config_file="env/watchtower.env"
    local errors=0

    # Проверка URL уведомлений
    if grep -q "^WATCHTOWER_NOTIFICATION_URL=" "$config_file"; then
        local url=$(grep "^WATCHTOWER_NOTIFICATION_URL=" "$config_file" | cut -d'=' -f2- | tr -d '"')

        if [[ "$url" =~ ^discord:// ]]; then
            success "Discord уведомления настроены"
        elif [[ "$url" =~ ^slack:// ]]; then
            success "Slack уведомления настроены"
        elif [[ "$url" =~ ^telegram:// ]]; then
            success "Telegram уведомления настроены"
        elif [[ "$url" =~ ^generic\+https?:// ]]; then
            success "Webhook уведомления настроены"
        else
            warning "Неизвестный тип уведомлений: $url"
            ((errors++))
        fi
    else
        warning "URL уведомлений не настроен"
        ((errors++))
    fi

    # Проверка шаблона
    if grep -q "^WATCHTOWER_NOTIFICATION_TEMPLATE=" "$config_file"; then
        success "Пользовательский шаблон уведомлений настроен"
    else
        log "Используется стандартный шаблон уведомлений"
    fi

    return $errors
}

# Показать справку
show_help() {
    cat << EOF
Скрипт тестирования уведомлений Watchtower

Использование: $0 [КОМАНДА]

Команды:
    check       - Проверить конфигурацию и статус
    test        - Протестировать отправку уведомлений
    validate    - Валидировать настройки уведомлений
    status      - Показать статус Watchtower
    help        - Показать эту справку

Примеры:
    $0 check     # Полная проверка
    $0 test      # Тестирование уведомлений
    $0 validate  # Валидация конфигурации

Перед использованием убедитесь, что:
1. Настроен WATCHTOWER_NOTIFICATION_URL в env/watchtower.env
2. Watchtower запущен и работает
3. У вас есть права на запуск Docker команд
EOF
}

# Основная функция
main() {
    local command="${1:-check}"

    case "$command" in
        "check")
            check_dependencies
            check_config
            check_watchtower_status
            validate_notification_config
            ;;
        "test")
            check_dependencies
            if check_config; then
                test_notifications
            else
                error "Конфигурация некорректна. Исправьте ошибки и попробуйте снова."
                exit 1
            fi
            ;;
        "validate")
            validate_notification_config
            ;;
        "status")
            check_watchtower_status
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            error "Неизвестная команда: $command"
            show_help
            exit 1
            ;;
    esac
}

# Проверка, что скрипт запущен из корневой директории проекта
if [[ ! -f "compose.yml" ]]; then
    error "Скрипт должен быть запущен из корневой директории проекта ERNI-KI"
    exit 1
fi

# Запуск основной функции
main "$@"
