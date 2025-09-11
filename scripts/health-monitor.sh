#!/bin/bash

# 🔍 ERNI-KI Health Monitor Script
# Автоматический мониторинг состояния системы после миграции PostgreSQL
# Создано: Альтэон Шульц, Tech Lead

set -euo pipefail

# === КОНФИГУРАЦИЯ ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/.config-backup/monitoring"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="$LOG_DIR/health-report-$TIMESTAMP.md"

# Создание директории для логов
mkdir -p "$LOG_DIR"

# === ЦВЕТА ДЛЯ ВЫВОДА ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# === ФУНКЦИИ ===
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$REPORT_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$REPORT_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$REPORT_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$REPORT_FILE"
}

# === ПРОВЕРКА СЕРВИСОВ ===
check_services() {
    log_info "=== ПРОВЕРКА СТАТУСА СЕРВИСОВ ==="

    cd "$PROJECT_DIR"

    # Получение статуса всех сервисов
    local services_status
    services_status=$(docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Health}}" 2>/dev/null || echo "ERROR: Cannot get services status")

    if [[ "$services_status" == "ERROR:"* ]]; then
        log_error "Не удалось получить статус сервисов"
        return 1
    fi

    echo "$services_status" >> "$REPORT_FILE"

    # Подсчет healthy сервисов
    local total_services healthy_services unhealthy_services
    total_services=$(echo "$services_status" | grep -c "erni-ki-" || echo "0")
    healthy_services=$(echo "$services_status" | grep -c "healthy" || echo "0")
    unhealthy_services=$((total_services - healthy_services))

    log_info "Всего сервисов: $total_services"
    log_info "Healthy сервисов: $healthy_services"

    if [[ $unhealthy_services -gt 0 ]]; then
        log_warning "Unhealthy сервисов: $unhealthy_services"
        return 1
    else
        log_success "Все сервисы в состоянии healthy"
        return 0
    fi
}

# === ПРОВЕРКА КРИТИЧЕСКИХ ОШИБОК ===
check_critical_errors() {
    log_info "=== ПРОВЕРКА КРИТИЧЕСКИХ ОШИБОК (последние 30 минут) ==="

    cd "$PROJECT_DIR"

    # Проверка ошибок в критических сервисах
    local critical_services=("db" "openwebui" "ollama" "nginx" "litellm")
    local total_errors=0

    for service in "${critical_services[@]}"; do
        local error_count
        error_count=$(docker-compose logs "$service" --since 30m 2>/dev/null | grep -c -E "(ERROR|FATAL|CRITICAL)" || echo "0")

        if [[ "$error_count" =~ ^[0-9]+$ ]] && [[ $error_count -gt 0 ]]; then
            log_warning "$service: $error_count ошибок за последние 30 минут"
            total_errors=$((total_errors + error_count))
        else
            log_success "$service: нет критических ошибок"
        fi
    done

    if [[ $total_errors -gt 5 ]]; then
        log_error "Слишком много ошибок: $total_errors (порог: 5)"
        return 1
    else
        log_success "Критические ошибки в пределах нормы: $total_errors"
        return 0
    fi
}

# === ПРОВЕРКА ПРОИЗВОДИТЕЛЬНОСТИ RAG ===
check_rag_performance() {
    log_info "=== ПРОВЕРКА ПРОИЗВОДИТЕЛЬНОСТИ RAG ==="

    local start_time end_time duration
    start_time=$(date +%s.%N)

    # Тест RAG поиска
    local rag_result
    rag_result=$(curl -s -w "%{time_total}" "http://localhost:8080/searxng/search?q=test&format=json" 2>/dev/null | tail -1 || echo "ERROR")

    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")

    if [[ "$rag_result" == "ERROR" ]]; then
        log_error "RAG поиск недоступен"
        return 1
    fi

    # Проверка времени ответа (цель <2s)
    if (( $(echo "$duration > 2.0" | bc -l) )); then
        log_warning "RAG поиск медленный: ${duration}s (цель <2s)"
        return 1
    else
        log_success "RAG поиск быстрый: ${duration}s"
        return 0
    fi
}

# === ПРОВЕРКА POSTGRESQL ===
check_postgresql() {
    log_info "=== ПРОВЕРКА POSTGRESQL pg17 ==="

    cd "$PROJECT_DIR"

    # Проверка версии PostgreSQL
    local pg_version
    pg_version=$(docker-compose exec -T db psql -U postgres -c "SELECT version();" 2>/dev/null | grep "PostgreSQL" || echo "ERROR")

    if [[ "$pg_version" == "ERROR" ]]; then
        log_error "PostgreSQL недоступен"
        return 1
    fi

    if [[ "$pg_version" == *"PostgreSQL 17"* ]]; then
        log_success "PostgreSQL 17 работает корректно"
    else
        log_warning "Неожиданная версия PostgreSQL: $pg_version"
    fi

    # Проверка pgvector
    local pgvector_version
    pgvector_version=$(docker-compose exec -T db psql -U postgres -c "SELECT extversion FROM pg_extension WHERE extname='vector';" 2>/dev/null | grep -E "0\.[0-9]" || echo "ERROR")

    if [[ "$pgvector_version" == "ERROR" ]]; then
        log_error "pgvector расширение недоступно"
        return 1
    else
        log_success "pgvector версия: $pgvector_version"
        return 0
    fi
}

# === ПРОВЕРКА WEBSOCKET ПРОБЛЕМ ===
check_websocket_issues() {
    log_info "=== ПРОВЕРКА WEBSOCKET ПРОБЛЕМ ==="

    cd "$PROJECT_DIR"

    # Проверка 400 ошибок WebSocket в OpenWebUI
    local websocket_errors
    websocket_errors=$(docker-compose logs openwebui --since 30m 2>/dev/null | grep -c "socket.io.*400" || echo "0")

    if [[ $websocket_errors -gt 10 ]]; then
        log_warning "Много WebSocket 400 ошибок: $websocket_errors (последние 30 мин)"
        log_info "Рекомендация: WebSocket отключен намеренно из-за проблем с Redis аутентификацией"
        return 1
    elif [[ $websocket_errors -gt 0 ]]; then
        log_info "WebSocket 400 ошибки: $websocket_errors (ожидаемо, WebSocket отключен)"
        return 0
    else
        log_success "Нет WebSocket ошибок"
        return 0
    fi
}

# === ГЛАВНАЯ ФУНКЦИЯ ===
main() {
    log_info "🔍 ERNI-KI Health Monitor - $(date)"
    log_info "Отчет сохранен: $REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    local exit_code=0

    # Выполнение всех проверок
    check_services || exit_code=1
    echo "" >> "$REPORT_FILE"

    check_critical_errors || exit_code=1
    echo "" >> "$REPORT_FILE"

    check_rag_performance || exit_code=1
    echo "" >> "$REPORT_FILE"

    check_postgresql || exit_code=1
    echo "" >> "$REPORT_FILE"

    check_websocket_issues || exit_code=1
    echo "" >> "$REPORT_FILE"

    # Итоговый статус
    if [[ $exit_code -eq 0 ]]; then
        log_success "🎉 ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ УСПЕШНО!"
        log_success "Система ERNI-KI работает стабильно"
    else
        log_warning "⚠️ ОБНАРУЖЕНЫ ПРОБЛЕМЫ"
        log_warning "Требуется внимание администратора"
    fi

    log_info "Следующая проверка рекомендуется через 1 час"

    return $exit_code
}

# === ЗАПУСК ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
