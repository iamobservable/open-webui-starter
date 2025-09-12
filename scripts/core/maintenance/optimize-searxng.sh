#!/bin/bash

# SearXNG Optimization Script for ERNI-KI
# Скрипт оптимизации SearXNG для проекта ERNI-KI

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции для логирования
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

    command -v openssl >/dev/null 2>&1 || error "openssl не найден"
    command -v docker >/dev/null 2>&1 || error "docker не найден"

    if command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE="docker-compose"
    elif docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE="docker compose"
    else
        error "docker-compose или docker compose не найден"
    fi

    success "Все зависимости найдены"
}

# Генерация безопасного секретного ключа
generate_searxng_secret() {
    log "Генерация безопасного секретного ключа для SearXNG..."

    local secret_key
    secret_key=$(openssl rand -hex 32)

    # Обновление env файла
    if [ -f "env/searxng.env" ]; then
        # Обновляем существующий файл
        sed -i "s/SEARXNG_SECRET=.*/SEARXNG_SECRET=${secret_key}/" env/searxng.env
    else
        # Создаем новый файл из примера
        cp env/searxng.example env/searxng.env
        sed -i "s/SEARXNG_SECRET=.*/SEARXNG_SECRET=${secret_key}/" env/searxng.env
    fi

    success "Секретный ключ сгенерирован и сохранен в env/searxng.env"
}

# Копирование конфигурационных файлов
copy_config_files() {
    log "Копирование обновленных конфигурационных файлов..."

    # SearXNG конфигурации
    if [ ! -f "conf/searxng/settings.yml" ]; then
        cp conf/searxng/settings.yml.example conf/searxng/settings.yml
        success "Скопирован conf/searxng/settings.yml"
    else
        warning "conf/searxng/settings.yml уже существует, создаем резервную копию"
        cp conf/searxng/settings.yml conf/searxng/settings.yml.backup.$(date +%Y%m%d_%H%M%S)
        cp conf/searxng/settings.yml.example conf/searxng/settings.yml
        success "Обновлен conf/searxng/settings.yml (создана резервная копия)"
    fi

    if [ ! -f "conf/searxng/uwsgi.ini" ]; then
        cp conf/searxng/uwsgi.ini.example conf/searxng/uwsgi.ini
        success "Скопирован conf/searxng/uwsgi.ini"
    else
        warning "conf/searxng/uwsgi.ini уже существует, создаем резервную копию"
        cp conf/searxng/uwsgi.ini conf/searxng/uwsgi.ini.backup.$(date +%Y%m%d_%H%M%S)
        cp conf/searxng/uwsgi.ini.example conf/searxng/uwsgi.ini
        success "Обновлен conf/searxng/uwsgi.ini (создана резервная копия)"
    fi

    # Nginx конфигурации
    if [ ! -f "conf/nginx/conf.d/default.conf" ]; then
        cp conf/nginx/conf.d/default.example conf/nginx/conf.d/default.conf
        success "Скопирован conf/nginx/conf.d/default.conf"
    else
        warning "conf/nginx/conf.d/default.conf уже существует, создаем резервную копию"
        cp conf/nginx/conf.d/default.conf conf/nginx/conf.d/default.conf.backup.$(date +%Y%m%d_%H%M%S)
        cp conf/nginx/conf.d/default.example conf/nginx/conf.d/default.conf
        success "Обновлен conf/nginx/conf.d/default.conf (создана резервная копия)"
    fi

    # Docker Compose
    if [ ! -f "compose.yml" ]; then
        cp compose.yml.example compose.yml
        success "Скопирован compose.yml"
    else
        warning "compose.yml уже существует, создаем резервную копию"
        cp compose.yml compose.yml.backup.$(date +%Y%m%d_%H%M%S)
        cp compose.yml.example compose.yml
        success "Обновлен compose.yml (создана резервная копия)"
    fi
}

# Проверка конфигурации
validate_config() {
    log "Проверка конфигурации..."

    # Проверка YAML файлов
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import yaml; yaml.safe_load(open('conf/searxng/settings.yml', 'r'))" || error "Ошибка в conf/searxng/settings.yml"
        success "conf/searxng/settings.yml валиден"
    fi

    # Проверка Docker Compose
    $DOCKER_COMPOSE config >/dev/null || error "Ошибка в compose.yml"
    success "compose.yml валиден"
}

# Перезапуск сервисов
restart_services() {
    log "Перезапуск SearXNG и связанных сервисов..."

    # Остановка SearXNG
    $DOCKER_COMPOSE stop searxng nginx || warning "Не удалось остановить некоторые сервисы"

    # Запуск с новой конфигурацией
    $DOCKER_COMPOSE up -d searxng nginx || error "Не удалось запустить сервисы"

    success "Сервисы перезапущены"
}

# Проверка работоспособности
health_check() {
    log "Проверка работоспособности SearXNG..."

    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -f -s http://localhost:8081/ >/dev/null 2>&1; then
            success "SearXNG доступен и работает"
            return 0
        fi

        log "Попытка $attempt/$max_attempts: ожидание запуска SearXNG..."
        sleep 2
        ((attempt++))
    done

    error "SearXNG не отвечает после $max_attempts попыток"
}

# Отображение статуса
show_status() {
    log "Статус сервисов:"
    $DOCKER_COMPOSE ps searxng nginx redis

    echo ""
    log "Проверка логов SearXNG (последние 10 строк):"
    $DOCKER_COMPOSE logs --tail=10 searxng
}

# Основная функция
main() {
    log "Запуск оптимизации SearXNG для ERNI-KI..."

    # Проверка, что мы в корне проекта
    if [ ! -f "compose.yml.example" ]; then
        error "Скрипт должен запускаться из корня проекта ERNI-KI"
    fi

    check_dependencies
    generate_searxng_secret
    copy_config_files
    validate_config
    restart_services
    health_check
    show_status

    success "Оптимизация SearXNG завершена успешно!"

    echo ""
    log "Следующие шаги:"
    echo "1. Проверьте работу SearXNG: http://localhost:8081/"
    echo "2. Проверьте интеграцию с OpenWebUI"
    echo "3. Мониторьте логи: $DOCKER_COMPOSE logs -f searxng"
    echo "4. Настройте мониторинг метрик uWSGI: http://localhost:9191"

    warning "ВАЖНО: Сохраните сгенерированный секретный ключ в безопасном месте!"
}

# Запуск скрипта
main "$@"
