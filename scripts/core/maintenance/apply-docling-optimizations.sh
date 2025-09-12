#!/bin/bash

# Скрипт применения оптимизаций Docling
# Основан на результатах комплексной диагностики

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

# Проверка прав доступа
check_permissions() {
    if [[ $EUID -eq 0 ]]; then
        error "Не запускайте этот скрипт от имени root"
        exit 1
    fi

    if ! command -v docker &> /dev/null; then
        error "Docker не установлен"
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose не установлен"
        exit 1
    fi
}

# Создание резервной копии
create_backup() {
    section "Создание резервной копии конфигурации"

    local backup_dir=".config-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"

    # Копирование конфигурационных файлов
    cp env/docling.env "$backup_dir/" 2>/dev/null || warning "env/docling.env не найден"
    cp compose.yml "$backup_dir/" 2>/dev/null || warning "compose.yml не найден"

    success "Резервная копия создана в $backup_dir"
}

# Проверка текущего статуса Docling
check_current_status() {
    section "Проверка текущего статуса Docling"

    # Проверка статуса контейнера
    if docker ps --filter "name=docling" --format "table {{.Names}}\t{{.Status}}" | grep -q "healthy"; then
        success "Контейнер Docling работает и здоров"
    else
        warning "Контейнер Docling не работает или нездоров"
    fi

    # Проверка API
    if curl -s --max-time 5 http://localhost:5001/health | grep -q "ok"; then
        success "API Docling отвечает корректно"
    else
        warning "API Docling не отвечает"
    fi
}

# Применение оптимизированной конфигурации
apply_optimizations() {
    section "Применение оптимизированной конфигурации"

    log "Проверка существования файла конфигурации..."
    if [[ ! -f "env/docling.env" ]]; then
        error "Файл env/docling.env не найден"
        exit 1
    fi

    # Проверка, применены ли уже оптимизации
    if grep -q "DOCLING_SERVE_MAX_WORKERS" env/docling.env; then
        success "Оптимизации уже применены"
        return 0
    fi

    warning "Оптимизации не обнаружены в конфигурации"
    log "Рекомендуется обновить env/docling.env согласно отчету диагностики"
}

# Перезапуск сервиса
restart_service() {
    section "Перезапуск сервиса Docling"

    log "Остановка сервиса Docling..."
    docker-compose stop docling

    log "Запуск сервиса Docling..."
    docker-compose up -d docling

    # Ожидание готовности сервиса
    log "Ожидание готовности сервиса..."
    local max_attempts=30
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if curl -s --max-time 5 http://localhost:5001/health | grep -q "ok"; then
            success "Сервис Docling готов к работе"
            break
        fi

        log "Попытка $attempt/$max_attempts - ожидание готовности..."
        sleep 2
        ((attempt++))
    done

    if [[ $attempt -gt $max_attempts ]]; then
        error "Сервис не готов после $max_attempts попыток"
        exit 1
    fi
}

# Проверка здоровья после изменений
health_check() {
    section "Проверка здоровья после применения изменений"

    # Проверка статуса контейнера
    local container_status=$(docker ps --filter "name=docling" --format "{{.Status}}")
    log "Статус контейнера: $container_status"

    # Проверка API
    log "Тестирование API..."
    local api_response=$(curl -s --max-time 10 http://localhost:5001/health)
    if echo "$api_response" | grep -q "ok"; then
        success "API работает корректно"
    else
        error "Проблемы с API: $api_response"
    fi

    # Проверка времени отклика
    log "Измерение времени отклика..."
    local response_time=$(curl -s -w "%{time_total}" --max-time 10 http://localhost:5001/health -o /dev/null)
    log "Время отклика: ${response_time}s"

    if (( $(echo "$response_time < 2.0" | bc -l) )); then
        success "Время отклика соответствует требованиям (< 2s)"
    else
        warning "Время отклика превышает рекомендуемое значение"
    fi
}

# Проверка логов
check_logs() {
    section "Проверка логов на наличие ошибок"

    log "Анализ последних 50 строк логов..."
    local error_count=$(docker logs erni-ki-docling-1 --tail 50 2>&1 | grep -c "ERROR" || true)

    if [[ $error_count -eq 0 ]]; then
        success "Ошибки в логах не обнаружены"
    else
        warning "Обнаружено $error_count ошибок в логах"
        log "Последние ошибки:"
        docker logs erni-ki-docling-1 --tail 20 2>&1 | grep "ERROR" || true
    fi
}

# Тестирование функциональности
test_functionality() {
    section "Тестирование функциональности"

    # Создание тестового файла
    local test_file="/tmp/docling_test.html"
    cat > "$test_file" << 'EOF'
<!DOCTYPE html>
<html>
<head><title>Test</title></head>
<body>
    <h1>Test Document</h1>
    <p>This is a test for Docling functionality.</p>
</body>
</html>
EOF

    log "Тестирование конвертации HTML → Markdown..."
    local test_result=$(curl -s --max-time 30 -X POST "http://localhost:5001/v1alpha/convert/file" \
        -H "Content-Type: multipart/form-data" \
        -F "files=@$test_file" \
        -F "output_format=markdown")

    if echo "$test_result" | grep -q "Test Document"; then
        success "Функциональное тестирование прошло успешно"
    else
        error "Проблемы с функциональностью: $test_result"
    fi

    # Очистка
    rm -f "$test_file"
}

# Отображение итогового статуса
show_final_status() {
    section "Итоговый статус системы"

    echo "📊 Статус сервисов:"
    docker ps --filter "name=docling" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

    echo ""
    echo "🔗 Доступные эндпоинты:"
    echo "  • Health Check: http://localhost:5001/health"
    echo "  • API Documentation: http://localhost:5001/docs"
    echo "  • Convert File: POST http://localhost:5001/v1alpha/convert/file"

    echo ""
    echo "📋 Следующие шаги:"
    echo "  1. Мониторинг логов: docker-compose logs -f docling"
    echo "  2. Тестирование в OpenWebUI с загрузкой документов"
    echo "  3. Проверка через неделю согласно рекомендациям"

    success "Применение оптимизаций Docling завершено!"
}

# Основная функция
main() {
    echo "🔍 Скрипт применения оптимизаций Docling для ERNI-KI"
    echo "Основан на результатах комплексной диагностики"
    echo ""

    check_permissions
    create_backup
    check_current_status
    apply_optimizations
    restart_service
    health_check
    check_logs
    test_functionality
    show_final_status
}

# Запуск основной функции
main "$@"
