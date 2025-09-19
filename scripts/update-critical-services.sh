#!/bin/bash

# ERNI-KI Critical Services Update Script
# Автоматизированное обновление критических сервисов с проверками безопасности
# Создан: 2025-09-11

set -euo pipefail

# Конфигурация
BACKUP_DIR=".config-backup"
DATE_STAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$BACKUP_DIR/update-log-$DATE_STAMP.log"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция логирования
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Функция для цветного вывода
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}$message${NC}" | tee -a "$LOG_FILE"
}

# Функция проверки статуса сервиса
check_service_health() {
    local service=$1
    local max_attempts=30
    local attempt=1

    log "Проверка здоровья сервиса: $service"

    while [ $attempt -le $max_attempts ]; do
        local status=$(docker-compose ps --format "{{.Service}}\t{{.Status}}" | grep "^$service" | awk '{print $2}')

        if [[ "$status" == *"healthy"* ]]; then
            print_status "$GREEN" "✅ $service: healthy"
            return 0
        elif [[ "$status" == *"starting"* ]]; then
            log "⏳ $service: starting (попытка $attempt/$max_attempts)"
            sleep 10
        else
            log "⚠️ $service: $status (попытка $attempt/$max_attempts)"
            sleep 5
        fi

        ((attempt++))
    done

    print_status "$RED" "❌ $service: не удалось достичь healthy статуса"
    return 1
}

# Функция создания бэкапа
create_backup() {
    local service=$1
    log "Создание бэкапа для $service"

    case $service in
        "ollama")
            docker exec erni-ki-ollama ollama list > "$BACKUP_DIR/ollama-models-$DATE_STAMP.txt" || true
            cp -r data/ollama "$BACKUP_DIR/ollama-backup-$DATE_STAMP" 2>/dev/null || true
            ;;
        "openwebui")
            docker-compose exec -T db pg_dump -U postgres openwebui > "$BACKUP_DIR/openwebui-db-$DATE_STAMP.sql" || true
            cp -r data/openwebui "$BACKUP_DIR/openwebui-backup-$DATE_STAMP" 2>/dev/null || true
            ;;
        "db")
            docker-compose exec -T db pg_dumpall -U postgres > "$BACKUP_DIR/postgres-full-$DATE_STAMP.sql" || true
            ;;
    esac
}

# Функция обновления Ollama
update_ollama() {
    print_status "$BLUE" "🔄 Обновление Ollama (0.11.8 → 0.11.10)"

    # Бэкап
    create_backup "ollama"

    # Остановить зависимые сервисы
    log "Остановка зависимых сервисов"
    docker-compose stop openwebui litellm vllm ollama-exporter || true

    # Обновить образ
    log "Загрузка нового образа Ollama"
    docker pull ollama/ollama:0.11.10

    # Обновить compose.yml
    log "Обновление конфигурации"
    sed -i.bak 's/ollama\/ollama:0.11.8/ollama\/ollama:0.11.10/g' compose.yml

    # Запустить Ollama
    log "Запуск Ollama"
    docker-compose up -d ollama

    # Проверить здоровье
    if check_service_health "ollama"; then
        # Проверить модели
        log "Проверка доступности моделей"
        docker exec erni-ki-ollama ollama list | tee -a "$LOG_FILE"

        # Запустить зависимые сервисы
        log "Запуск зависимых сервисов"
        docker-compose up -d openwebui litellm ollama-exporter

        # Проверить их здоровье
        for service in openwebui litellm; do
            check_service_health "$service"
        done

        print_status "$GREEN" "✅ Ollama успешно обновлен"
        return 0
    else
        print_status "$RED" "❌ Ошибка обновления Ollama"
        return 1
    fi
}

# Функция обновления OpenWebUI
update_openwebui() {
    print_status "$BLUE" "🔄 Обновление OpenWebUI"

    # Бэкап
    create_backup "openwebui"

    # Остановить nginx и openwebui
    log "Остановка nginx и OpenWebUI"
    docker-compose stop nginx openwebui

    # Обновить образ
    log "Загрузка нового образа OpenWebUI"
    docker pull ghcr.io/open-webui/open-webui:latest

    # Запустить OpenWebUI
    log "Запуск OpenWebUI"
    docker-compose up -d openwebui

    # Проверить здоровье
    if check_service_health "openwebui"; then
        # Проверить API
        log "Проверка API OpenWebUI"
        if curl -s -f http://localhost:8080/health >/dev/null; then
            log "✅ OpenWebUI API доступен"
        else
            log "⚠️ OpenWebUI API недоступен"
        fi

        # Запустить nginx
        log "Запуск nginx"
        docker-compose up -d nginx
        check_service_health "nginx"

        print_status "$GREEN" "✅ OpenWebUI успешно обновлен"
        return 0
    else
        print_status "$RED" "❌ Ошибка обновления OpenWebUI"
        return 1
    fi
}

# Функция обновления LiteLLM
update_litellm() {
    print_status "$BLUE" "🔄 Обновление LiteLLM"

    # Обновить образ
    log "Загрузка нового образа LiteLLM"
    docker-compose pull litellm

    # Перезапустить
    log "Перезапуск LiteLLM"
    docker-compose up -d litellm

    # Проверить здоровье и память
    if check_service_health "litellm"; then
        log "Проверка использования памяти"
        docker stats --no-stream erni-ki-litellm | tee -a "$LOG_FILE"

        print_status "$GREEN" "✅ LiteLLM успешно обновлен"
        return 0
    else
        print_status "$RED" "❌ Ошибка обновления LiteLLM"
        return 1
    fi
}

# Функция финальной проверки системы
final_system_check() {
    print_status "$BLUE" "🔍 Финальная проверка системы"

    # Проверить все критические сервисы
    local critical_services=("db" "redis" "ollama" "litellm" "openwebui" "nginx")
    local failed_services=()

    for service in "${critical_services[@]}"; do
        if ! check_service_health "$service"; then
            failed_services+=("$service")
        fi
    done

    if [ ${#failed_services[@]} -eq 0 ]; then
        print_status "$GREEN" "✅ Все критические сервисы работают корректно"

        # Проверить функциональность
        log "Проверка функциональности системы"

        # OpenWebUI
        if curl -s -f http://localhost:8080/health >/dev/null; then
            log "✅ OpenWebUI API работает"
        else
            log "⚠️ OpenWebUI API недоступен"
        fi

        # Ollama
        if curl -s -f http://localhost:11434/api/tags >/dev/null; then
            log "✅ Ollama API работает"
        else
            log "⚠️ Ollama API недоступен"
        fi

        # RAG интеграция
        if curl -s -f "http://localhost:8080/api/searxng/search?q=test&format=json" >/dev/null; then
            log "✅ RAG интеграция работает"
        else
            log "⚠️ RAG интеграция недоступна"
        fi

        print_status "$GREEN" "🎉 Обновление критических сервисов завершено успешно!"
        return 0
    else
        print_status "$RED" "❌ Обнаружены проблемы с сервисами: ${failed_services[*]}"
        return 1
    fi
}

# Основная функция
main() {
    print_status "$BLUE" "🚀 Начало обновления критических сервисов ERNI-KI"
    log "Лог файл: $LOG_FILE"

    # Создать директорию для бэкапов
    mkdir -p "$BACKUP_DIR"

    # Создать бэкап конфигурации
    log "Создание бэкапа конфигурации"
    cp compose.yml "compose.yml.backup-$DATE_STAMP"
    cp -r env "env-backup-$DATE_STAMP" 2>/dev/null || true

    # Проверить начальное состояние
    log "Проверка начального состояния системы"
    docker-compose ps | tee -a "$LOG_FILE"

    # Выполнить обновления
    local success=true

    # 1. Ollama
    if ! update_ollama; then
        success=false
    fi

    # 2. OpenWebUI (только если Ollama успешно обновлен)
    if $success && ! update_openwebui; then
        success=false
    fi

    # 3. LiteLLM
    if $success && ! update_litellm; then
        success=false
    fi

    # Финальная проверка
    if $success && final_system_check; then
        print_status "$GREEN" "🎉 ВСЕ ОБНОВЛЕНИЯ ЗАВЕРШЕНЫ УСПЕШНО!"
        log "Время завершения: $(date)"
        exit 0
    else
        print_status "$RED" "❌ ОБНАРУЖЕНЫ ОШИБКИ ПРИ ОБНОВЛЕНИИ"
        print_status "$YELLOW" "📋 Проверьте лог файл: $LOG_FILE"
        print_status "$YELLOW" "🔄 Рассмотрите возможность отката изменений"
        exit 1
    fi
}

# Проверка прав и зависимостей
if [[ $EUID -eq 0 ]]; then
   echo "Не запускайте этот скрипт от root"
   exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "docker-compose не найден"
    exit 1
fi

# Запуск основной функции
main "$@"
