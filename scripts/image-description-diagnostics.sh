#!/bin/bash

# Скрипт диагностики для подготовки включения функции описания изображений
# Автор: Альтэон Шульц (ERNI-KI Tech Lead)

set -euo pipefail

echo "🔍 ERNI-KI: Диагностика готовности к включению функции описания изображений"
echo "============================================================================"

# Функция логирования
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Проверка статуса сервисов
check_services() {
    log "Проверка статуса критических сервисов..."

    local services=("docling" "ollama" "openwebui" "db")
    local all_healthy=true

    for service in "${services[@]}"; do
        if docker-compose ps "$service" | grep -q "healthy"; then
            log "✅ $service: Здоров"
        else
            log "❌ $service: Проблемы со здоровьем"
            all_healthy=false
        fi
    done

    if [ "$all_healthy" = true ]; then
        log "✅ Все критические сервисы здоровы"
        return 0
    else
        log "❌ Обнаружены проблемы с сервисами"
        return 1
    fi
}

# Проверка доступности Ollama API
check_ollama_api() {
    log "Проверка доступности Ollama API..."

    if curl -s http://localhost:11434/api/tags > /dev/null; then
        log "✅ Ollama API доступен"

        # Проверка наличия llava модели
        if curl -s http://localhost:11434/api/tags | grep -q "llava"; then
            log "✅ Модель llava найдена в Ollama"
            return 0
        else
            log "⚠️  Модель llava не найдена. Требуется загрузка: ollama pull llava:latest"
            return 1
        fi
    else
        log "❌ Ollama API недоступен"
        return 1
    fi
}

# Проверка Docling API
check_docling_api() {
    log "Проверка Docling API..."

    if docker-compose exec docling curl -s http://localhost:5001/health | grep -q "ok"; then
        log "✅ Docling API здоров"

        # Проверка endpoints
        if docker-compose exec docling curl -s http://localhost:5001/openapi.json | jq -r '.paths | keys[]' | grep -q "convert"; then
            log "✅ Docling convert endpoints доступны"
            return 0
        else
            log "❌ Docling convert endpoints недоступны"
            return 1
        fi
    else
        log "❌ Docling API недоступен"
        return 1
    fi
}

# Проверка свободного места
check_disk_space() {
    log "Проверка свободного места на диске..."

    local available_gb=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')

    if [ "$available_gb" -gt 10 ]; then
        log "✅ Свободного места: ${available_gb}GB (достаточно)"
        return 0
    else
        log "⚠️  Свободного места: ${available_gb}GB (рекомендуется >10GB для моделей)"
        return 1
    fi
}

# Проверка памяти
check_memory() {
    log "Проверка доступной памяти..."

    local available_mb=$(free -m | awk 'NR==2{printf "%.0f", $7}')

    if [ "$available_mb" -gt 4096 ]; then
        log "✅ Доступной памяти: ${available_mb}MB (достаточно)"
        return 0
    else
        log "⚠️  Доступной памяти: ${available_mb}MB (рекомендуется >4GB для VLM моделей)"
        return 1
    fi
}

# Проверка GPU (если доступен)
check_gpu() {
    log "Проверка доступности GPU..."

    if command -v nvidia-smi &> /dev/null; then
        local gpu_memory=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | head -1)
        if [ "$gpu_memory" -gt 2048 ]; then
            log "✅ GPU доступен, свободной памяти: ${gpu_memory}MB"
            return 0
        else
            log "⚠️  GPU доступен, но мало свободной памяти: ${gpu_memory}MB"
            return 1
        fi
    else
        log "ℹ️  GPU не обнаружен (будет использоваться CPU)"
        return 0
    fi
}

# Создание резервной копии конфигурации
create_config_backup() {
    log "Создание резервной копии текущей конфигурации..."

    local backup_dir=".config-backup/image-description-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"

    # Копирование критических файлов конфигурации
    cp env/docling.env "$backup_dir/"
    cp compose.yml "$backup_dir/"

    # Экспорт настроек OpenWebUI (если возможно)
    if docker-compose exec openwebui test -f /app/backend/data/config.json; then
        docker-compose exec openwebui cat /app/backend/data/config.json > "$backup_dir/openwebui-config.json"
    fi

    log "✅ Резервная копия создана в: $backup_dir"
    echo "$backup_dir" > .config-backup/latest-image-description-backup
}

# Основная функция
main() {
    local all_checks_passed=true

    # Выполнение всех проверок
    check_services || all_checks_passed=false
    check_ollama_api || all_checks_passed=false
    check_docling_api || all_checks_passed=false
    check_disk_space || all_checks_passed=false
    check_memory || all_checks_passed=false
    check_gpu || all_checks_passed=false

    # Создание резервной копии независимо от результатов проверок
    create_config_backup

    echo ""
    echo "============================================================================"

    if [ "$all_checks_passed" = true ]; then
        log "🎉 Система готова к включению функции описания изображений!"
        log "📋 Рекомендуется начать с Варианта 2 (API mode с Ollama)"
        exit 0
    else
        log "⚠️  Обнаружены проблемы. Рекомендуется их устранить перед продолжением."
        log "📋 Проверьте логи выше и устраните указанные проблемы."
        exit 1
    fi
}

# Запуск основной функции
main "$@"
