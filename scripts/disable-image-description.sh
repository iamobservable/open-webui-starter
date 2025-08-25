#!/bin/bash

# Скрипт отключения функции описания изображений и восстановления стабильной конфигурации
# Автор: Альтэон Шульц (ERNI-KI Tech Lead)

set -euo pipefail

echo "🔄 ERNI-KI: Отключение функции описания изображений"
echo "=================================================="

# Функция логирования
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Восстановление стабильной конфигурации Docling
restore_stable_config() {
    log "⚙️  Восстановление стабильной конфигурации Docling..."
    
    # Обновление env/docling.env для стабильности
    sed -i 's/DOCLING_DISABLE_VLM=false/DOCLING_DISABLE_VLM=true/' env/docling.env
    sed -i 's/DOCLING_USE_LOCAL_MODELS=false/DOCLING_USE_LOCAL_MODELS=true/' env/docling.env
    sed -i 's/DOCLING_DISABLE_IMAGE_PROCESSING=false/DOCLING_DISABLE_IMAGE_PROCESSING=true/' env/docling.env
    sed -i 's/DOCLING_FORCE_SIMPLE_PIPELINE=false/DOCLING_FORCE_SIMPLE_PIPELINE=true/' env/docling.env
    
    # Обновление compose.yml
    sed -i 's/DOCLING_DISABLE_IMAGE_PROCESSING: false/DOCLING_DISABLE_IMAGE_PROCESSING: true/' compose.yml
    
    log "✅ Стабильная конфигурация восстановлена"
}

# Перезапуск Docling
restart_docling() {
    log "🔄 Перезапуск Docling со стабильной конфигурацией..."
    
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

# Проверка логов на отсутствие ошибок
check_logs() {
    log "🔍 Проверка логов Docling на отсутствие ошибок..."
    
    sleep 10  # Ожидание накопления логов
    
    local error_count=$(docker-compose logs --tail=50 docling | grep -c "ERROR\|Task result not found\|SmolVLM\|VLM" || true)
    
    if [ "$error_count" -eq 0 ]; then
        log "✅ Ошибки в логах Docling отсутствуют"
        return 0
    else
        log "⚠️  Обнаружено $error_count ошибок в логах Docling"
        log "📋 Последние логи Docling:"
        docker-compose logs --tail=20 docling
        return 1
    fi
}

# Проверка статуса всех сервисов
check_all_services() {
    log "🔍 Проверка статуса всех сервисов..."
    
    local unhealthy_services=$(docker-compose ps | grep -v "healthy" | grep -c "Up" || true)
    
    if [ "$unhealthy_services" -eq 0 ]; then
        local total_services=$(docker-compose ps | grep -c "Up" || true)
        log "✅ Все $total_services сервисов работают корректно"
        return 0
    else
        log "⚠️  Обнаружены проблемы с некоторыми сервисами"
        docker-compose ps | grep -v "healthy" | grep "Up" || true
        return 1
    fi
}

# Тестирование основной функциональности Docling
test_basic_functionality() {
    log "🧪 Тестирование основной функциональности Docling..."
    
    # Проверка health endpoint
    if docker-compose exec docling curl -s http://localhost:5001/health | grep -q "ok"; then
        log "✅ Docling health endpoint работает"
    else
        log "❌ Проблемы с Docling health endpoint"
        return 1
    fi
    
    # Проверка convert endpoints
    if docker-compose exec docling curl -s http://localhost:5001/openapi.json | jq -r '.paths | keys[]' | grep -q "convert"; then
        log "✅ Docling convert endpoints доступны"
    else
        log "❌ Проблемы с Docling convert endpoints"
        return 1
    fi
    
    return 0
}

# Создание отчета о состоянии системы
create_status_report() {
    log "📊 Создание отчета о состоянии системы..."
    
    local report_file=".config-backup/system-status-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "ERNI-KI System Status Report"
        echo "Generated: $(date)"
        echo "================================"
        echo ""
        echo "Docker Compose Services:"
        docker-compose ps
        echo ""
        echo "Docling Logs (last 20 lines):"
        docker-compose logs --tail=20 docling
        echo ""
        echo "System Resources:"
        free -h
        df -h .
        echo ""
        echo "Configuration Status:"
        echo "- Image Description: DISABLED"
        echo "- Docling VLM: DISABLED"
        echo "- Docling Image Processing: DISABLED"
        echo "- System Mode: STABLE"
    } > "$report_file"
    
    log "✅ Отчет сохранен в: $report_file"
}

# Рекомендации по устранению проблем
provide_recommendations() {
    log "💡 Рекомендации по устранению проблем:"
    log "   1. Проверьте логи: docker-compose logs docling ollama openwebui"
    log "   2. Убедитесь в достаточности ресурсов (RAM >4GB, Disk >10GB)"
    log "   3. Проверьте сетевое подключение между контейнерами"
    log "   4. При необходимости выполните полный перезапуск: docker-compose restart"
    log "   5. Для диагностики используйте: ./scripts/image-description-diagnostics.sh"
}

# Основная функция
main() {
    log "🔄 Начало процесса отключения функции описания изображений..."
    
    # Выполнение всех этапов
    restore_stable_config
    restart_docling
    
    # Проверки с обработкой ошибок
    local all_checks_passed=true
    
    check_logs || all_checks_passed=false
    check_all_services || all_checks_passed=false
    test_basic_functionality || all_checks_passed=false
    
    # Создание отчета независимо от результатов
    create_status_report
    
    echo ""
    echo "=================================================="
    
    if [ "$all_checks_passed" = true ]; then
        log "🎉 Функция описания изображений успешно отключена!"
        log "✅ Система работает в стабильном режиме"
        log "📋 Основная функциональность Docling восстановлена"
    else
        log "⚠️  Функция отключена, но обнаружены некоторые проблемы"
        provide_recommendations
    fi
    
    echo "=================================================="
}

# Запуск основной функции
main "$@"
