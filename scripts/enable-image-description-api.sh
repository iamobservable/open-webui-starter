#!/bin/bash

# Скрипт включения функции описания изображений через API mode с Ollama
# Автор: Альтэон Шульц (ERNI-KI Tech Lead)

set -euo pipefail

echo "🚀 ERNI-KI: Включение функции описания изображений (API mode с Ollama)"
echo "========================================================================"

# Функция логирования
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Функция отката изменений
rollback() {
    log "🔄 Выполнение отката изменений..."

    if [ -f .config-backup/latest-image-description-backup ]; then
        local backup_dir=$(cat .config-backup/latest-image-description-backup)
        if [ -d "$backup_dir" ]; then
            cp "$backup_dir/docling.env" env/
            cp "$backup_dir/compose.yml" .
            log "✅ Конфигурация восстановлена из резервной копии"

            # Перезапуск Docling
            docker-compose restart docling
            log "✅ Docling перезапущен с восстановленной конфигурацией"
        fi
    fi
}

# Обработчик сигналов для отката
trap rollback ERR

# Проверка наличия llava модели в Ollama
ensure_llava_model() {
    log "🔍 Проверка наличия модели llava в Ollama..."

    if ! curl -s http://localhost:11434/api/tags | grep -q "llava"; then
        log "📥 Загрузка модели llava:latest..."
        docker-compose exec ollama ollama pull llava:latest

        # Ожидание завершения загрузки
        while ! curl -s http://localhost:11434/api/tags | grep -q "llava"; do
            log "⏳ Ожидание завершения загрузки модели..."
            sleep 10
        done

        log "✅ Модель llava:latest успешно загружена"
    else
        log "✅ Модель llava уже доступна"
    fi
}

# Тестирование llava модели
test_llava_model() {
    log "🧪 Тестирование модели llava..."

    # Создание простого тестового запроса
    local test_response=$(curl -s -X POST http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d '{"model": "llava:latest", "prompt": "Hello", "stream": false}' \
        | jq -r '.response // "error"' 2>/dev/null || echo "error")

    if [ "$test_response" != "error" ] && [ -n "$test_response" ]; then
        log "✅ Модель llava отвечает корректно"
        return 0
    else
        log "❌ Проблемы с моделью llava"
        return 1
    fi
}

# Настройка Docling для remote services
configure_docling() {
    log "⚙️  Настройка Docling для работы с remote services..."

    # Обновление env/docling.env
    sed -i 's/DOCLING_DISABLE_VLM=true/DOCLING_DISABLE_VLM=false/' env/docling.env
    sed -i 's/DOCLING_USE_LOCAL_MODELS=true/DOCLING_USE_LOCAL_MODELS=false/' env/docling.env
    sed -i 's/DOCLING_DISABLE_IMAGE_PROCESSING=true/DOCLING_DISABLE_IMAGE_PROCESSING=false/' env/docling.env
    sed -i 's/DOCLING_FORCE_SIMPLE_PIPELINE=true/DOCLING_FORCE_SIMPLE_PIPELINE=false/' env/docling.env

    # Обновление compose.yml
    sed -i 's/DOCLING_DISABLE_IMAGE_PROCESSING: true/DOCLING_DISABLE_IMAGE_PROCESSING: false/' compose.yml

    log "✅ Конфигурация Docling обновлена"
}

# Перезапуск Docling
restart_docling() {
    log "🔄 Перезапуск Docling с новой конфигурацией..."

    docker-compose restart docling

    # Ожидание готовности Docling
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if docker-compose ps docling | grep -q "healthy"; then
            log "✅ Docling успешно перезапущен и здоров"
            return 0
        fi

        attempt=$((attempt + 1))
        log "⏳ Ожидание готовности Docling... ($attempt/$max_attempts)"
        sleep 5
    done

    log "❌ Docling не стал здоровым в течение ожидаемого времени"
    return 1
}

# Настройка OpenWebUI через API
configure_openwebui() {
    log "⚙️  Настройка OpenWebUI для описания изображений..."

    # JSON конфигурация для API mode
    local api_config='{
        "url": "http://ollama:11434/v1/chat/completions",
        "params": {"model": "llava:latest"},
        "timeout": 60,
        "prompt": "Describe this image in detail, focusing on key visual elements, text content, and any important information that would be useful for document search and retrieval."
    }'

    # Попытка настройки через веб-интерфейс (требует ручного вмешательства)
    log "📋 Для завершения настройки выполните следующие действия в веб-интерфейсе:"
    log "   1. Откройте http://localhost:8080/admin/settings/documents"
    log "   2. Включите 'Describe Pictures in Documents'"
    log "   3. Выберите режим 'API' в Picture Description Mode"
    log "   4. Вставьте следующую JSON конфигурацию:"
    echo "$api_config" | jq .
    log "   5. Нажмите 'Save'"

    # Сохранение конфигурации в файл для справки
    echo "$api_config" > .config-backup/openwebui-image-api-config.json
    log "✅ Конфигурация сохранена в .config-backup/openwebui-image-api-config.json"
}

# Тестирование интеграции
test_integration() {
    log "🧪 Тестирование интеграции Docling ↔ Ollama..."

    # Проверка доступности Docling API
    if ! docker-compose exec openwebui curl -s http://docling:5001/health | grep -q "ok"; then
        log "❌ Docling API недоступен"
        return 1
    fi

    # Проверка доступности Ollama
    if ! curl -s http://localhost:11434/api/tags > /dev/null; then
        log "❌ Ollama API недоступен"
        return 1
    fi

    log "✅ Базовая интеграция работает корректно"
    return 0
}

# Мониторинг логов
monitor_logs() {
    log "📊 Мониторинг логов для проверки работы функции..."
    log "   Выполните команду для мониторинга:"
    log "   docker-compose logs -f docling ollama openwebui"
    log ""
    log "   Ожидаемые признаки успешной работы:"
    log "   - Отсутствие ошибок 'Task result not found' в логах Docling"
    log "   - Успешные запросы к Ollama API в логах"
    log "   - Отсутствие ошибок VLM/SmolVLM в логах"
}

# Основная функция
main() {
    log "🚀 Начало процесса включения функции описания изображений..."

    # Выполнение всех этапов
    ensure_llava_model
    test_llava_model
    configure_docling
    restart_docling
    test_integration
    configure_openwebui
    monitor_logs

    echo ""
    echo "========================================================================"
    log "🎉 Функция описания изображений настроена (API mode)!"
    log "📋 Следующие шаги:"
    log "   1. Завершите настройку OpenWebUI через веб-интерфейс"
    log "   2. Протестируйте загрузку документов с изображениями"
    log "   3. Мониторьте логи на предмет ошибок"
    log "   4. При проблемах выполните: ./scripts/disable-image-description.sh"
    echo "========================================================================"
}

# Запуск основной функции
main "$@"
