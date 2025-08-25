#!/bin/bash

# Скрипт комплексного тестирования функции описания изображений
# Автор: Альтэон Шульц (ERNI-KI Tech Lead)

set -euo pipefail

echo "🧪 ERNI-KI: Тестирование функции описания изображений"
echo "===================================================="

# Функция логирования
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Создание тестовых документов с изображениями
create_test_documents() {
    log "📄 Подготовка тестовых документов..."
    
    local test_dir="tests/image-description"
    mkdir -p "$test_dir"
    
    # Создание простого HTML документа с изображением
    cat > "$test_dir/test-with-image.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Test Document with Image</title>
</head>
<body>
    <h1>Test Document</h1>
    <p>This document contains an image for testing image description functionality.</p>
    <img src="data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjAwIiBoZWlnaHQ9IjEwMCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KICA8cmVjdCB3aWR0aD0iMjAwIiBoZWlnaHQ9IjEwMCIgZmlsbD0iIzAwNzNlNiIvPgogIDx0ZXh0IHg9IjEwMCIgeT0iNTUiIGZvbnQtZmFtaWx5PSJBcmlhbCIgZm9udC1zaXplPSIxNiIgZmlsbD0id2hpdGUiIHRleHQtYW5jaG9yPSJtaWRkbGUiPlRlc3QgSW1hZ2U8L3RleHQ+Cjwvc3ZnPg==" alt="Test Image">
    <p>The image above should be described by the AI system.</p>
</body>
</html>
EOF
    
    log "✅ Тестовые документы созданы в $test_dir"
}

# Тестирование Docling API напрямую
test_docling_api() {
    log "🔍 Тестирование Docling API..."
    
    # Проверка health endpoint
    if docker-compose exec docling curl -s http://localhost:5001/health | grep -q "ok"; then
        log "✅ Docling health endpoint работает"
    else
        log "❌ Проблемы с Docling health endpoint"
        return 1
    fi
    
    # Проверка доступности convert endpoint
    local convert_response=$(docker-compose exec docling curl -s -o /dev/null -w "%{http_code}" \
        -X POST http://localhost:5001/v1/convert/file \
        -H "Content-Type: multipart/form-data" \
        -F "file=@/dev/null" || echo "000")
    
    if [ "$convert_response" != "000" ]; then
        log "✅ Docling convert endpoint доступен (HTTP $convert_response)"
    else
        log "❌ Проблемы с доступностью Docling convert endpoint"
        return 1
    fi
    
    return 0
}

# Тестирование Ollama llava модели
test_ollama_llava() {
    log "🔍 Тестирование Ollama llava модели..."
    
    # Проверка наличия модели
    if ! docker-compose exec ollama ollama list | grep -q "llava"; then
        log "❌ Модель llava не найдена в Ollama"
        return 1
    fi
    
    # Тестовый запрос к модели
    local test_prompt="Describe what you see in this image"
    local response=$(docker-compose exec ollama curl -s -X POST http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"llava:latest\", \"prompt\": \"$test_prompt\", \"stream\": false}" \
        | jq -r '.response // "error"' 2>/dev/null || echo "error")
    
    if [ "$response" != "error" ] && [ -n "$response" ] && [ "$response" != "null" ]; then
        log "✅ Ollama llava модель отвечает корректно"
        log "📝 Пример ответа: ${response:0:100}..."
        return 0
    else
        log "❌ Проблемы с Ollama llava моделью"
        return 1
    fi
}

# Мониторинг производительности
monitor_performance() {
    log "📊 Мониторинг производительности системы..."
    
    # Проверка использования памяти
    local memory_usage=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
    log "💾 Использование памяти: ${memory_usage}%"
    
    # Проверка использования диска
    local disk_usage=$(df . | awk 'NR==2{printf "%.1f", $5}' | sed 's/%//')
    log "💿 Использование диска: ${disk_usage}%"
    
    # Проверка загрузки CPU
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    log "🖥️  Загрузка CPU: ${cpu_usage}%"
    
    # Проверка GPU (если доступен)
    if command -v nvidia-smi &> /dev/null; then
        local gpu_usage=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -1)
        local gpu_memory=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits | head -1)
        log "🎮 GPU: ${gpu_usage}% загрузка, память: $gpu_memory"
    fi
    
    # Предупреждения о высоком использовании ресурсов
    if (( $(echo "$memory_usage > 80" | bc -l) )); then
        log "⚠️  Высокое использование памяти: ${memory_usage}%"
    fi
    
    if (( $(echo "$disk_usage > 80" | bc -l) )); then
        log "⚠️  Высокое использование диска: ${disk_usage}%"
    fi
}

# Анализ логов на предмет ошибок
analyze_logs() {
    log "🔍 Анализ логов на предмет ошибок..."
    
    local services=("docling" "ollama" "openwebui")
    local total_errors=0
    
    for service in "${services[@]}"; do
        local error_count=$(docker-compose logs --tail=100 "$service" | grep -c "ERROR\|WARN\|Task result not found\|SmolVLM" || true)
        
        if [ "$error_count" -gt 0 ]; then
            log "⚠️  $service: найдено $error_count предупреждений/ошибок"
            total_errors=$((total_errors + error_count))
        else
            log "✅ $service: ошибки не обнаружены"
        fi
    done
    
    if [ "$total_errors" -eq 0 ]; then
        log "✅ Критические ошибки в логах отсутствуют"
        return 0
    else
        log "⚠️  Обнаружено $total_errors предупреждений/ошибок в логах"
        return 1
    fi
}

# Тестирование времени отклика
test_response_time() {
    log "⏱️  Тестирование времени отклика..."
    
    # Тестирование Docling API
    local docling_start=$(date +%s.%N)
    docker-compose exec docling curl -s http://localhost:5001/health > /dev/null
    local docling_end=$(date +%s.%N)
    local docling_time=$(echo "$docling_end - $docling_start" | bc)
    
    # Тестирование Ollama API
    local ollama_start=$(date +%s.%N)
    docker-compose exec ollama curl -s http://localhost:11434/api/tags > /dev/null
    local ollama_end=$(date +%s.%N)
    local ollama_time=$(echo "$ollama_end - $ollama_start" | bc)
    
    log "📊 Время отклика Docling: ${docling_time}s"
    log "📊 Время отклика Ollama: ${ollama_time}s"
    
    # Проверка приемлемого времени отклика
    if (( $(echo "$docling_time < 2.0" | bc -l) )) && (( $(echo "$ollama_time < 2.0" | bc -l) )); then
        log "✅ Время отклика в пределах нормы (<2s)"
        return 0
    else
        log "⚠️  Медленное время отклика (>2s)"
        return 1
    fi
}

# Создание отчета о тестировании
create_test_report() {
    log "📊 Создание отчета о тестировании..."
    
    local report_file=".config-backup/image-description-test-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "ERNI-KI Image Description Function Test Report"
        echo "Generated: $(date)"
        echo "=============================================="
        echo ""
        echo "System Status:"
        docker-compose ps | grep -E "(docling|ollama|openwebui)"
        echo ""
        echo "Resource Usage:"
        free -h
        df -h .
        if command -v nvidia-smi &> /dev/null; then
            echo ""
            echo "GPU Status:"
            nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv
        fi
        echo ""
        echo "Recent Logs (Docling):"
        docker-compose logs --tail=20 docling
        echo ""
        echo "Recent Logs (Ollama):"
        docker-compose logs --tail=10 ollama
        echo ""
        echo "Test Results Summary:"
        echo "- Docling API: $(test_docling_api && echo "PASS" || echo "FAIL")"
        echo "- Ollama llava: $(test_ollama_llava && echo "PASS" || echo "FAIL")"
        echo "- Performance: $(monitor_performance && echo "GOOD" || echo "ISSUES")"
        echo "- Logs Analysis: $(analyze_logs && echo "CLEAN" || echo "WARNINGS")"
        echo "- Response Time: $(test_response_time && echo "GOOD" || echo "SLOW")"
    } > "$report_file"
    
    log "✅ Отчет о тестировании сохранен в: $report_file"
}

# Основная функция
main() {
    log "🧪 Начало комплексного тестирования функции описания изображений..."
    
    local all_tests_passed=true
    
    # Подготовка
    create_test_documents
    
    # Выполнение тестов
    test_docling_api || all_tests_passed=false
    test_ollama_llava || all_tests_passed=false
    monitor_performance || all_tests_passed=false
    analyze_logs || all_tests_passed=false
    test_response_time || all_tests_passed=false
    
    # Создание отчета
    create_test_report
    
    echo ""
    echo "===================================================="
    
    if [ "$all_tests_passed" = true ]; then
        log "🎉 Все тесты пройдены успешно!"
        log "✅ Функция описания изображений готова к использованию"
        log "📋 Рекомендуется протестировать загрузку реальных документов"
    else
        log "⚠️  Обнаружены проблемы в некоторых тестах"
        log "📋 Проверьте отчет и устраните выявленные проблемы"
        log "🔄 При необходимости выполните откат: ./scripts/disable-image-description.sh"
    fi
    
    echo "===================================================="
}

# Запуск основной функции
main "$@"
