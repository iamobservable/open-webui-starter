#!/bin/bash
# Скрипт настройки Backrest для ERNI-KI
# Автоматизирует развертывание и первоначальную конфигурацию системы бэкапов

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

# Проверка зависимостей
check_dependencies() {
    log "Проверка зависимостей..."

    if ! command -v docker &> /dev/null; then
        error "Docker не установлен. Установите Docker и повторите попытку."
    fi

    # Проверяем наличие Docker Compose (любой версии)
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        error "Docker Compose не установлен. Установите Docker Compose и повторите попытку."
    fi

    if [ ! -f "compose.yml" ] && [ ! -f "compose.yml.example" ]; then
        error "Файлы compose.yml или compose.yml.example не найдены. Запустите скрипт из корня проекта ERNI-KI."
    fi

    # Если compose.yml не существует, но есть example, копируем его
    if [ ! -f "compose.yml" ] && [ -f "compose.yml.example" ]; then
        log "Копирование compose.yml.example в compose.yml..."
        cp compose.yml.example compose.yml
        success "Скопирован compose.yml из примера"
    fi

    success "Все зависимости проверены"
}

# Создание необходимых директорий
create_directories() {
    log "Создание директорий для Backrest..."

    directories=(
        "data/backrest"
        "conf/backrest"
        "cache/backrest"
        "tmp/backrest"
        "logs/backrest"
    )

    for dir in "${directories[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            success "Создана директория: $dir"
        else
            warning "Директория уже существует: $dir"
        fi
    done
}

# Копирование конфигурационных файлов
setup_config_files() {
    log "Настройка конфигурационных файлов..."

    # Копирование файла переменных окружения
    if [ ! -f "env/backrest.env" ]; then
        if [ -f "env/backrest.example" ]; then
            cp "env/backrest.example" "env/backrest.env"
            success "Скопирован env/backrest.env"
        else
            error "Файл env/backrest.example не найден"
        fi
    else
        warning "Файл env/backrest.env уже существует"
    fi

    # Копирование конфигурации Backrest
    if [ ! -f "conf/backrest/config.json" ]; then
        if [ -f "conf/backrest/config.example.json" ]; then
            cp "conf/backrest/config.example.json" "conf/backrest/config.json"
            success "Скопирован conf/backrest/config.json"
        else
            error "Файл conf/backrest/config.example.json не найден"
        fi
    else
        warning "Файл conf/backrest/config.json уже существует"
    fi
}

# Генерация секретных ключей
generate_secrets() {
    log "Генерация секретных ключей..."

    # Генерация пароля для Backrest (только буквы и цифры для избежания проблем с sed)
    BACKREST_PASSWORD=$(openssl rand -hex 16)

    # Генерация ключа шифрования для restic (только буквы и цифры)
    RESTIC_PASSWORD=$(openssl rand -hex 24)

    # Обновление файла переменных окружения с использованием более безопасного подхода
    if [ -f "env/backrest.env" ]; then
        # Создаем временный файл для безопасной замены
        cp "env/backrest.env" "env/backrest.env.tmp"

        # Используем awk для более безопасной замены
        awk -v new_pass="$BACKREST_PASSWORD" '
            /^BACKREST_PASSWORD=CHANGE_BEFORE_GOING_LIVE/ {
                print "BACKREST_PASSWORD=" new_pass
                next
            }
            {print}
        ' "env/backrest.env.tmp" > "env/backrest.env.new"

        awk -v new_pass="$RESTIC_PASSWORD" '
            /^RESTIC_PASSWORD=CHANGE_BEFORE_GOING_LIVE_BACKUP_ENCRYPTION_KEY/ {
                print "RESTIC_PASSWORD=" new_pass
                next
            }
            {print}
        ' "env/backrest.env.new" > "env/backrest.env"

        # Удаляем временные файлы
        rm -f "env/backrest.env.tmp" "env/backrest.env.new"

        success "Обновлены пароли в env/backrest.env"
    fi

    # Обновление конфигурации Backrest
    if [ -f "conf/backrest/config.json" ]; then
        # Используем более безопасную замену для JSON
        awk -v new_pass="$RESTIC_PASSWORD" '
            gsub(/CHANGE_BEFORE_GOING_LIVE_BACKUP_ENCRYPTION_KEY/, new_pass)
            {print}
        ' "conf/backrest/config.json" > "conf/backrest/config.json.new"

        mv "conf/backrest/config.json.new" "conf/backrest/config.json"
        success "Обновлен ключ шифрования в config.json"
    fi

    # Сохранение ключей в файл для справки
    cat > .backrest_secrets << EOF
# ERNI-KI Backrest Секретные ключи - $(date)
# ВНИМАНИЕ: Храните этот файл в безопасности!

BACKREST_PASSWORD=$BACKREST_PASSWORD
RESTIC_PASSWORD=$RESTIC_PASSWORD

# Эти ключи уже применены к конфигурационным файлам
# Сохраните их в безопасном месте (например, в менеджере паролей)
EOF

    chmod 600 .backrest_secrets
    success "Секретные ключи сохранены в .backrest_secrets"
}

# Проверка конфигурации Docker Compose
check_compose_config() {
    log "Проверка конфигурации Docker Compose..."

    if ! grep -q "backrest:" compose.yml; then
        error "Сервис backrest не найден в compose.yml. Обновите файл compose.yml из compose.yml.example"
    fi

    success "Конфигурация Docker Compose корректна"
}

# Запуск Backrest
start_backrest() {
    log "Запуск сервиса Backrest..."

    # Определяем команду Docker Compose
    if command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE="docker-compose"
    elif docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
    else
        error "Docker Compose не найден"
    fi

    # Остановка существующего контейнера (если есть)
    $DOCKER_COMPOSE stop backrest 2>/dev/null || true
    $DOCKER_COMPOSE rm -f backrest 2>/dev/null || true

    # Запуск нового контейнера
    $DOCKER_COMPOSE up -d backrest

    # Ожидание запуска
    log "Ожидание запуска Backrest..."
    sleep 15

    # Проверка состояния
    if $DOCKER_COMPOSE ps backrest | grep -q "Up"; then
        success "Backrest успешно запущен"
        log "Веб-интерфейс доступен по адресу: http://localhost:9898"
        log "Или через Nginx proxy: http://your-domain/backrest"
    else
        error "Не удалось запустить Backrest. Проверьте логи: $DOCKER_COMPOSE logs backrest"
    fi
}

# Создание первого бэкапа
create_initial_backup() {
    log "Проверка доступности Backrest..."

    # Ожидание полной инициализации Backrest
    sleep 10

    # Проверка доступности веб-интерфейса
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:9898/ | grep -q "200"; then
        success "Backrest веб-интерфейс доступен"
        log "Первый бэкап будет создан автоматически по расписанию"
        log "Вы можете создать бэкап вручную через веб-интерфейс"
    else
        warning "Backrest веб-интерфейс недоступен. Проверьте состояние сервиса"
    fi
}

# Вывод информации о завершении
show_completion_info() {
    echo ""
    success "Настройка Backrest завершена!"
    echo ""
    log "Следующие шаги:"
    echo "1. Откройте веб-интерфейс Backrest: http://localhost:9898"
    echo "2. Войдите используя учетные данные из .backrest_secrets"
    echo "3. Проверьте конфигурацию репозиториев и планов бэкапов"
    echo "4. Настройте внешнее хранилище (S3, B2, SFTP) при необходимости"
    echo "5. Протестируйте создание и восстановление бэкапов"
    echo ""
    warning "ВАЖНО:"
    echo "- Сохраните файл .backrest_secrets в безопасном месте"
    echo "- Настройте мониторинг бэкапов"
    echo "- Регулярно тестируйте процедуры восстановления"
    echo "- Рассмотрите настройку внешнего хранилища для критически важных данных"
}

# Основная функция
main() {
    log "Запуск настройки Backrest для ERNI-KI..."

    check_dependencies
    create_directories
    setup_config_files
    generate_secrets
    check_compose_config
    start_backrest
    create_initial_backup
    show_completion_info
}

# Запуск скрипта
main "$@"
