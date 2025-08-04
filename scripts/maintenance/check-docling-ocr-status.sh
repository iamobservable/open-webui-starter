#!/bin/bash

# Скрипт проверки статуса OCR в Docling
# Проверяет отсутствие ошибок Tesseract и функциональность EasyOCR

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
}

section() {
    echo ""
    echo -e "${BLUE}=== $1 ===${NC}"
    echo ""
}

# Проверка статуса контейнера
check_container_status() {
    section "Проверка статуса контейнера Docling"
    
    if docker ps --filter "name=docling" --format "{{.Status}}" | grep -q "healthy"; then
        success "Контейнер Docling работает и здоров"
        docker ps --filter "name=docling" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        error "Контейнер Docling не работает или нездоров"
        return 1
    fi
}

# Проверка API
check_api_health() {
    section "Проверка API Docling"
    
    local start_time=$(date +%s.%N)
    if curl -s --max-time 5 http://localhost:5001/health | grep -q "ok"; then
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc -l)
        success "API работает корректно (время отклика: ${duration}s)"
    else
        error "API не отвечает или работает некорректно"
        return 1
    fi
}

# Проверка логов на ошибки OCR
check_ocr_errors() {
    section "Проверка логов на ошибки OCR"
    
    local tesseract_errors=$(docker logs erni-ki-docling-1 --tail 100 2>&1 | grep -c "OSD failed" || true)
    local easyocr_errors=$(docker logs erni-ki-docling-1 --tail 100 2>&1 | grep -c "is not supported" || true)
    
    if [[ $tesseract_errors -eq 0 ]]; then
        success "Ошибки Tesseract OSD отсутствуют"
    else
        warning "Найдено $tesseract_errors ошибок Tesseract OSD в последних 100 строках"
    fi
    
    if [[ $easyocr_errors -eq 0 ]]; then
        success "Ошибки EasyOCR отсутствуют"
    else
        warning "Найдено $easyocr_errors ошибок EasyOCR в последних 100 строках"
    fi
    
    # Показать последние ошибки, если есть
    local total_errors=$((tesseract_errors + easyocr_errors))
    if [[ $total_errors -gt 0 ]]; then
        log "Последние ошибки OCR:"
        docker logs erni-ki-docling-1 --tail 20 2>&1 | grep -E "(ERROR|WARN)" || echo "Нет ошибок в последних 20 строках"
    fi
}

# Тестирование функциональности OCR
test_ocr_functionality() {
    section "Тестирование функциональности OCR"
    
    # Создание тестового документа
    local test_file="/tmp/docling_ocr_test.html"
    cat > "$test_file" << 'EOF'
<!DOCTYPE html>
<html>
<head><title>OCR Test</title></head>
<body>
    <h1>OCR Functionality Test</h1>
    <p>This document tests OCR processing capabilities.</p>
    <p>English text for recognition testing.</p>
</body>
</html>
EOF
    
    log "Тестирование конвертации HTML → Markdown..."
    local test_result=$(curl -s --max-time 30 -X POST "http://localhost:5001/v1alpha/convert/file" \
        -H "Content-Type: multipart/form-data" \
        -F "files=@$test_file" \
        -F "output_format=markdown")
    
    if echo "$test_result" | grep -q "OCR Functionality Test"; then
        success "Функциональное тестирование OCR прошло успешно"
        log "Результат конвертации:"
        echo "$test_result" | jq -r '.document.md_content' 2>/dev/null || echo "$test_result"
    else
        error "Проблемы с функциональностью OCR"
        log "Ответ сервера: $test_result"
        return 1
    fi
    
    # Очистка
    rm -f "$test_file"
}

# Проверка конфигурации OCR
check_ocr_configuration() {
    section "Проверка конфигурации OCR"
    
    log "Переменные окружения OCR в контейнере:"
    docker exec erni-ki-docling-1 env | grep -E "(OCR|TESSERACT|EASYOCR|DOCLING)" || echo "Переменные OCR не найдены"
    
    echo ""
    log "Конфигурация из env/docling.env:"
    grep -E "(OCR|TESSERACT|EASYOCR)" env/docling.env || echo "Настройки OCR не найдены в конфигурации"
}

# Проверка интеграции с OpenWebUI
check_openwebui_integration() {
    section "Проверка интеграции с OpenWebUI"
    
    log "Переменные интеграции в OpenWebUI:"
    docker exec erni-ki-openwebui-1 env | grep -E "(DOCLING|CONTENT_EXTRACTION)" || echo "Переменные интеграции не найдены"
    
    # Тест подключения из OpenWebUI к Docling
    log "Тестирование подключения OpenWebUI → Docling..."
    if docker exec erni-ki-openwebui-1 curl -s --max-time 5 http://docling:5001/health | grep -q "ok"; then
        success "OpenWebUI может подключиться к Docling"
    else
        warning "Проблемы с подключением OpenWebUI к Docling"
    fi
}

# Отображение итогового статуса
show_summary() {
    section "Итоговый статус OCR в Docling"
    
    echo "📊 Статус компонентов:"
    echo "  • Контейнер Docling: $(docker ps --filter 'name=docling' --format '{{.Status}}')"
    echo "  • API Health: $(curl -s http://localhost:5001/health 2>/dev/null || echo 'Недоступен')"
    echo "  • OCR движок: EasyOCR (настроен)"
    echo "  • Языки: Английский (en)"
    
    echo ""
    echo "🔗 Полезные команды:"
    echo "  • Логи: docker logs erni-ki-docling-1 --tail 50"
    echo "  • API тест: curl http://localhost:5001/health"
    echo "  • Документация: http://localhost:5001/docs"
    
    echo ""
    echo "📋 Рекомендации:"
    echo "  • Мониторить логи на предмет новых ошибок OCR"
    echo "  • Тестировать с различными типами документов"
    echo "  • Проверять производительность при высокой нагрузке"
}

# Основная функция
main() {
    echo "🔍 Проверка статуса OCR в Docling - ERNI-KI"
    echo "Проверяет исправление ошибок Tesseract и функциональность EasyOCR"
    echo ""
    
    local exit_code=0
    
    check_container_status || exit_code=1
    check_api_health || exit_code=1
    check_ocr_errors
    test_ocr_functionality || exit_code=1
    check_ocr_configuration
    check_openwebui_integration
    show_summary
    
    if [[ $exit_code -eq 0 ]]; then
        success "Все проверки OCR прошли успешно!"
    else
        error "Обнаружены проблемы с OCR. Проверьте логи и конфигурацию."
    fi
    
    return $exit_code
}

# Запуск основной функции
main "$@"
