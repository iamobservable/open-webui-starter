#!/bin/bash

# Скрипт проверки доступности всех веб-интерфейсов ERNI-KI
# Автор: Альтэон Шульц (ERNI-KI Tech Lead)

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Параметры
VERBOSE=false
MAIN_ONLY=false
TIMEOUT=10

# Функции логирования
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

header() {
    echo -e "${PURPLE}=== $1 ===${NC}"
}

# Функция проверки URL
check_url() {
    local name="$1"
    local url="$2"
    local expected_codes="${3:-200,302,307}"

    local status_code
    status_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout $TIMEOUT "$url" 2>/dev/null || echo "000")

    if [[ ",$expected_codes," == *",$status_code,"* ]]; then
        success "$(printf "%-25s %-30s %s" "$name" "$url" "$status_code")"
        return 0
    else
        error "$(printf "%-25s %-30s %s" "$name" "$url" "$status_code")"
        return 1
    fi
}

# Проверка основных AI-сервисов
check_ai_services() {
    header "AI СЕРВИСЫ"
    printf "%-25s %-30s %s\n" "SERVICE" "URL" "STATUS"
    echo "------------------------------------------------------------------------"

    local failed=0

    check_url "OpenWebUI (Local)" "http://localhost:8080" "200" || ((failed++))
    check_url "OpenWebUI (HTTPS)" "https://diz.zone" "200" || ((failed++))
    check_url "LiteLLM" "http://localhost:4000" "200,404" || ((failed++))

    echo ""
    if [ $failed -eq 0 ]; then
        success "Все AI-сервисы доступны"
    else
        warning "$failed AI-сервисов недоступны"
    fi

    return $failed
}

# Проверка мониторинга
check_monitoring() {
    header "МОНИТОРИНГ И АНАЛИТИКА"
    printf "%-25s %-30s %s\n" "SERVICE" "URL" "STATUS"
    echo "------------------------------------------------------------------------"

    local failed=0

    check_url "Grafana" "http://localhost:3000" "200,302" || ((failed++))
    check_url "Prometheus" "http://localhost:9091" "200,302" || ((failed++))
    check_url "Alertmanager" "http://localhost:9093" "200" || ((failed++))
    check_url "Loki" "http://localhost:3100/ready" "200,204" || ((failed++))

    echo ""
    if [ $failed -eq 0 ]; then
        success "Все сервисы мониторинга доступны"
    else
        warning "$failed сервисов мониторинга недоступны"
    fi

    return $failed
}

# Проверка администрирования
check_admin() {
    header "АДМИНИСТРИРОВАНИЕ"
    printf "%-25s %-30s %s\n" "SERVICE" "URL" "STATUS"
    echo "------------------------------------------------------------------------"

    local failed=0

    check_url "Backrest" "http://localhost:9898" "200" || ((failed++))
    check_url "Auth Server" "http://localhost:9090" "200,404" || ((failed++))
    check_url "cAdvisor" "http://localhost:8081" "200,307" || ((failed++))
    check_url "Tika" "http://localhost:9998" "200" || ((failed++))

    echo ""
    if [ $failed -eq 0 ]; then
        success "Все административные сервисы доступны"
    else
        warning "$failed административных сервисов недоступны"
    fi

    return $failed
}

# Проверка exporters
check_exporters() {
    header "EXPORTERS И МЕТРИКИ"
    printf "%-25s %-30s %s\n" "SERVICE" "URL" "STATUS"
    echo "------------------------------------------------------------------------"

    local failed=0

    check_url "Node Exporter" "http://localhost:9101/metrics" "200" || ((failed++))
    check_url "PostgreSQL Exporter" "http://localhost:9187/metrics" "200" || ((failed++))
    check_url "Redis Exporter" "http://localhost:9121/metrics" "200" || ((failed++))
    check_url "NVIDIA Exporter" "http://localhost:9445/metrics" "200" || ((failed++))
    check_url "Blackbox Exporter" "http://localhost:9115/metrics" "200" || ((failed++))
    check_url "Webhook Receiver" "http://localhost:9095/health" "200" || ((failed++))

    echo ""
    if [ $failed -eq 0 ]; then
        success "Все exporters доступны"
    else
        warning "$failed exporters недоступны"
    fi

    return $failed
}

# Проверка учетных данных
check_credentials() {
    header "УЧЕТНЫЕ ДАННЫЕ"
    echo "Основные учетные данные для доступа:"
    echo ""
    echo "OpenWebUI:"
    echo "  Email: diz-admin@proton.me"
    echo "  Password: testpass"
    echo "  URL: https://diz.zone"
    echo ""
    echo "Grafana:"
    echo "  Login: admin"
    echo "  Password: erni-ki-admin-2025"
    echo "  URL: http://localhost:3000"
    echo ""
    echo "Backrest:"
    echo "  Login: admin"
    echo "  Password: (не установлен - настроить!)"
    echo "  URL: http://localhost:9898"
    echo ""
    warning "ВАЖНО: Смените пароли по умолчанию в production!"
}

# Сводка результатов
show_summary() {
    local total_failed=$1

    header "СВОДКА РЕЗУЛЬТАТОВ"

    if [ $total_failed -eq 0 ]; then
        success "🎉 ВСЕ ВЕБ-ИНТЕРФЕЙСЫ ДОСТУПНЫ!"
        echo ""
        echo "✅ AI-сервисы: Работают"
        echo "✅ Мониторинг: Работает"
        echo "✅ Администрирование: Работает"
        echo "✅ Exporters: Работают"
        echo ""
        echo "Система ERNI-KI полностью готова к работе!"
    else
        error "⚠️ ОБНАРУЖЕНЫ ПРОБЛЕМЫ: $total_failed сервисов недоступны"
        echo ""
        echo "Рекомендации:"
        echo "1. Проверьте логи проблемных сервисов"
        echo "2. Убедитесь что все контейнеры запущены"
        echo "3. Проверьте сетевые настройки"
        echo "4. Перезапустите проблемные сервисы"
    fi
}

# Показать помощь
show_help() {
    echo "Использование: $0 [OPTIONS]"
    echo ""
    echo "Опции:"
    echo "  --main-only    Проверить только основные сервисы"
    echo "  --verbose      Подробный вывод"
    echo "  --timeout N    Таймаут подключения (по умолчанию: 10 сек)"
    echo "  --help         Показать эту справку"
    echo ""
    echo "Примеры:"
    echo "  $0                    # Полная проверка"
    echo "  $0 --main-only       # Только основные сервисы"
    echo "  $0 --verbose         # С подробным выводом"
}

# Обработка аргументов
while [[ $# -gt 0 ]]; do
    case $1 in
        --main-only)
            MAIN_ONLY=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "Неизвестная опция: $1"
            show_help
            exit 1
            ;;
    esac
done

# Основная функция
main() {
    echo "=================================================="
    echo "🔍 ПРОВЕРКА ВЕБ-ИНТЕРФЕЙСОВ ERNI-KI"
    echo "=================================================="
    echo "Дата: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Хост: $(hostname)"
    echo "Таймаут: ${TIMEOUT}s"
    echo ""

    local total_failed=0

    # Проверка AI-сервисов
    check_ai_services || total_failed=$((total_failed + $?))
    echo ""

    # Проверка мониторинга
    check_monitoring || total_failed=$((total_failed + $?))
    echo ""

    # Проверка администрирования
    check_admin || total_failed=$((total_failed + $?))
    echo ""

    # Проверка exporters (если не только основные)
    if [ "$MAIN_ONLY" = false ]; then
        check_exporters || total_failed=$((total_failed + $?))
        echo ""
    fi

    # Показать учетные данные (если verbose)
    if [ "$VERBOSE" = true ]; then
        check_credentials
        echo ""
    fi

    # Сводка
    show_summary $total_failed
    echo ""
    echo "=================================================="

    # Возврат кода ошибки если есть проблемы
    exit $total_failed
}

# Запуск
main "$@"
