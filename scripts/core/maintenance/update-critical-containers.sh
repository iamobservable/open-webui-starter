#!/bin/bash
# Скрипт критических обновлений ERNI-KI контейнеров
# Автор: Альтэон Шульц, Tech Lead
# Дата: 29 августа 2025

set -euo pipefail

# === КОНФИГУРАЦИЯ ===
BACKUP_DIR=".backups/$(date +%Y%m%d_%H%M%S)"
COMPOSE_FILE="compose.yml"

# === ЦВЕТА ДЛЯ ЛОГИРОВАНИЯ ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# === ФУНКЦИИ ЛОГИРОВАНИЯ ===
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

# === ПРОВЕРКА ПРЕДВАРИТЕЛЬНЫХ УСЛОВИЙ ===
check_prerequisites() {
    log "Проверка предварительных условий..."

    # Проверка Docker
    if ! command -v docker &> /dev/null; then
        error "Docker не установлен"
    fi

    # Проверка docker-compose
    if ! command -v docker-compose &> /dev/null; then
        error "docker-compose не установлен"
    fi

    # Проверка compose файла
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        error "Файл $COMPOSE_FILE не найден"
    fi

    # Проверка доступности сервисов
    if ! docker-compose ps | grep -q "Up"; then
        error "ERNI-KI сервисы не запущены. Запустите: docker-compose up -d"
    fi

    success "Предварительные условия выполнены"
}

# === СОЗДАНИЕ BACKUP ===
create_backup() {
    log "Создание backup критических данных..."

    mkdir -p "$BACKUP_DIR"

    # Backup PostgreSQL
    log "Backup базы данных PostgreSQL..."
    if docker-compose exec -T db pg_dump -U postgres openwebui > "$BACKUP_DIR/openwebui-backup.sql"; then
        success "PostgreSQL backup создан: $BACKUP_DIR/openwebui-backup.sql"
    else
        error "Не удалось создать backup PostgreSQL"
    fi

    # Backup Ollama моделей
    log "Backup списка Ollama моделей..."
    if docker-compose exec -T ollama ollama list > "$BACKUP_DIR/ollama-models.txt"; then
        success "Ollama models backup создан: $BACKUP_DIR/ollama-models.txt"
    else
        warning "Не удалось создать backup Ollama моделей"
    fi

    # Backup конфигурации
    log "Backup конфигурационных файлов..."
    cp "$COMPOSE_FILE" "$BACKUP_DIR/compose.yml.backup"
    if [[ -d "env" ]]; then
        cp -r env "$BACKUP_DIR/"
    fi
    if [[ -d "conf" ]]; then
        cp -r conf "$BACKUP_DIR/"
    fi

    success "Backup завершен: $BACKUP_DIR"
}

# === ОБНОВЛЕНИЕ OLLAMA ===
update_ollama() {
    log "Обновление Ollama: 0.11.6 → 0.11.8..."

    # Проверка текущей версии
    local current_version
    current_version=$(docker-compose exec -T ollama ollama --version 2>/dev/null | grep -o "v[0-9]\+\.[0-9]\+\.[0-9]\+" || echo "unknown")
    log "Текущая версия Ollama: $current_version"

    # Загрузка нового образа
    log "Загрузка ollama/ollama:0.11.8..."
    if ! docker pull ollama/ollama:0.11.8; then
        error "Не удалось загрузить новый образ Ollama"
    fi

    # Остановка сервиса
    log "Остановка Ollama..."
    docker-compose stop ollama

    # Обновление compose файла
    log "Обновление compose.yml..."
    sed -i.bak 's|ollama/ollama:0\.11\.6|ollama/ollama:0.11.8|g' "$COMPOSE_FILE"

    # Запуск обновленного сервиса
    log "Запуск обновленного Ollama..."
    docker-compose up -d ollama

    # Ожидание запуска
    log "Ожидание запуска Ollama (30 секунд)..."
    sleep 30

    # Проверка работоспособности
    local retry_count=0
    local max_retries=5

    while [[ $retry_count -lt $max_retries ]]; do
        if curl -f http://localhost:11434/api/tags >/dev/null 2>&1; then
            success "✅ Ollama обновлен успешно до версии 0.11.8"

            # Проверка новой версии
            local new_version
            new_version=$(docker-compose exec -T ollama ollama --version 2>/dev/null | grep -o "v[0-9]\+\.[0-9]\+\.[0-9]\+" || echo "unknown")
            log "Новая версия Ollama: $new_version"

            return 0
        else
            ((retry_count++))
            log "Попытка $retry_count/$max_retries: Ollama еще не готов, ожидание 10 секунд..."
            sleep 10
        fi
    done

    error "❌ Ollama не отвечает после обновления. Проверьте логи: docker-compose logs ollama"
}

# === ОБНОВЛЕНИЕ OPENWEBUI ===
update_openwebui() {
    log "Обновление OpenWebUI: cuda → v0.6.26..."

    # Загрузка нового образа
    log "Загрузка ghcr.io/open-webui/open-webui:v0.6.26..."
    if ! docker pull ghcr.io/open-webui/open-webui:v0.6.26; then
        error "Не удалось загрузить новый образ OpenWebUI"
    fi

    # Остановка сервиса
    log "Остановка OpenWebUI..."
    docker-compose stop openwebui

    # Обновление compose файла
    log "Обновление compose.yml..."
    sed -i.bak 's|ghcr\.io/open-webui/open-webui:cuda|ghcr.io/open-webui/open-webui:v0.6.26|g' "$COMPOSE_FILE"

    # Запуск обновленного сервиса
    log "Запуск обновленного OpenWebUI..."
    docker-compose up -d openwebui

    # Ожидание запуска
    log "Ожидание запуска OpenWebUI (60 секунд)..."
    sleep 60

    # Проверка работоспособности
    local retry_count=0
    local max_retries=10

    while [[ $retry_count -lt $max_retries ]]; do
        if curl -f http://localhost:8080/health >/dev/null 2>&1; then
            success "✅ OpenWebUI обновлен успешно до версии v0.6.26"
            return 0
        else
            ((retry_count++))
            log "Попытка $retry_count/$max_retries: OpenWebUI еще не готов, ожидание 15 секунд..."
            sleep 15
        fi
    done

    error "❌ OpenWebUI не отвечает после обновления. Проверьте логи: docker-compose logs openwebui"
}

# === ПРОВЕРКА СИСТЕМЫ ПОСЛЕ ОБНОВЛЕНИЯ ===
post_update_check() {
    log "Проверка системы после обновления..."

    echo ""
    echo "=== Статус контейнеров ==="
    docker-compose ps

    echo ""
    echo "=== Проверка доступности сервисов ==="

    # Проверка Ollama
    if curl -f http://localhost:11434/api/tags >/dev/null 2>&1; then
        success "✅ Ollama доступен"
    else
        warning "⚠️ Ollama недоступен"
    fi

    # Проверка OpenWebUI
    if curl -f http://localhost:8080/health >/dev/null 2>&1; then
        success "✅ OpenWebUI доступен"
    else
        warning "⚠️ OpenWebUI недоступен"
    fi

    # Проверка PostgreSQL
    if docker-compose exec -T db pg_isready -U postgres >/dev/null 2>&1; then
        success "✅ PostgreSQL доступен"
    else
        warning "⚠️ PostgreSQL недоступен"
    fi

    echo ""
    echo "=== Использование ресурсов ==="
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

    echo ""
    echo "=== Последние логи (возможные ошибки) ==="
    docker-compose logs --tail=20 | grep -i error || echo "Ошибок не найдено"
}

# === ФУНКЦИЯ ОТКАТА ===
rollback() {
    local service="$1"

    error "Выполняется откат $service..."

    case "$service" in
        "ollama")
            docker-compose stop ollama
            sed -i 's|ollama/ollama:0\.11\.8|ollama/ollama:0.11.6|g' "$COMPOSE_FILE"
            docker-compose up -d ollama
            ;;
        "openwebui")
            docker-compose stop openwebui
            sed -i 's|ghcr\.io/open-webui/open-webui:v0\.6\.26|ghcr.io/open-webui/open-webui:cuda|g' "$COMPOSE_FILE"
            docker-compose up -d openwebui
            ;;
    esac

    warning "Откат $service завершен. Проверьте работоспособность."
}

# === ОСНОВНАЯ ФУНКЦИЯ ===
main() {
    echo "🚀 Критические обновления ERNI-KI контейнеров"
    echo "=============================================="
    echo ""
    echo "Планируемые обновления:"
    echo "- Ollama: 0.11.6 → 0.11.8"
    echo "- OpenWebUI: cuda → v0.6.26"
    echo ""

    read -p "Продолжить обновление? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Обновление отменено пользователем"
        exit 0
    fi

    # Выполнение обновлений
    check_prerequisites
    create_backup

    # Обновление Ollama
    if update_ollama; then
        success "Ollama обновлен успешно"
    else
        rollback "ollama"
        exit 1
    fi

    # Обновление OpenWebUI
    if update_openwebui; then
        success "OpenWebUI обновлен успешно"
    else
        rollback "openwebui"
        exit 1
    fi

    # Финальная проверка
    post_update_check

    echo ""
    success "✅ Критические обновления завершены успешно!"
    echo ""
    echo "📋 Что было обновлено:"
    echo "- Ollama: 0.11.6 → 0.11.8 (улучшена производительность gpt-oss)"
    echo "- OpenWebUI: cuda → v0.6.26 (новые функции и исправления)"
    echo ""
    echo "📁 Backup сохранен в: $BACKUP_DIR"
    echo ""
    echo "🔍 Рекомендуется:"
    echo "1. Мониторить логи в течение 30 минут: docker-compose logs -f"
    echo "2. Протестировать RAG функциональность через веб-интерфейс"
    echo "3. Проверить производительность генерации ответов"
    echo ""
    echo "📚 В случае проблем:"
    echo "- Логи Ollama: docker-compose logs ollama"
    echo "- Логи OpenWebUI: docker-compose logs openwebui"
    echo "- Откат: восстановите compose.yml из $BACKUP_DIR/compose.yml.backup"
}

# === ОБРАБОТКА СИГНАЛОВ ===
trap 'error "Обновление прервано пользователем"' INT TERM

# === ЗАПУСК ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
