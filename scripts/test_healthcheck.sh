#!/bin/bash
# Скрипт тестирования healthcheck конфигурации ERNI-KI
# Автор: Альтэон Шульц (Tech Lead)

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции логирования
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Определение команды Docker Compose
get_compose_cmd() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    elif docker compose version &> /dev/null; then
        echo "docker compose"
    else
        error "Docker Compose не найден"
        exit 1
    fi
}

# Проверка Docker Compose конфигурации
check_compose_config() {
    log "Проверка Docker Compose конфигурации..."

    local compose_cmd=$(get_compose_cmd)

    if $compose_cmd config > /dev/null 2>&1; then
        success "Docker Compose конфигурация валидна"
    else
        error "Ошибка в Docker Compose конфигурации"
        $compose_cmd config
        exit 1
    fi
}

# Проверка healthcheck команд в compose.yml
check_healthcheck_commands() {
    log "Проверка healthcheck команд..."

    local compose_cmd=$(get_compose_cmd)

    # Извлекаем все healthcheck команды из compose.yml
    services_with_healthcheck=$($compose_cmd config | grep -A 10 "healthcheck:" | grep -E "test:|CMD" | wc -l)

    if [ "$services_with_healthcheck" -gt 0 ]; then
        success "Найдено $services_with_healthcheck healthcheck команд"

        # Показываем детали healthcheck конфигураций
        echo -e "\n${BLUE}Детали healthcheck конфигураций:${NC}"
        $compose_cmd config | grep -A 15 "healthcheck:" | grep -E "(test|interval|timeout|retries|start_period):" | while read -r line; do
            echo "  $line"
        done
    else
        warning "Healthcheck команды не найдены"
    fi
}

# Проверка зависимостей сервисов
check_service_dependencies() {
    log "Проверка зависимостей сервисов..."

    local compose_cmd=$(get_compose_cmd)

    # Проверяем наличие condition: service_healthy
    healthy_conditions=$($compose_cmd config | grep -c "condition: service_healthy" || echo "0")

    if [ "$healthy_conditions" -gt 0 ]; then
        success "Найдено $healthy_conditions зависимостей с condition: service_healthy"
    else
        warning "Зависимости с condition: service_healthy не найдены"
    fi
}

# Тестирование запуска сервисов
test_service_startup() {
    log "Тестирование запуска сервисов..."

    local compose_cmd=$(get_compose_cmd)

    # Останавливаем все сервисы
    $compose_cmd down > /dev/null 2>&1 || true

    # Запускаем сервисы в фоновом режиме
    log "Запуск сервисов..."
    $compose_cmd up -d

    # Ждем 30 секунд для инициализации
    log "Ожидание инициализации сервисов (30 сек)..."
    sleep 30

    # Проверяем статус сервисов
    log "Проверка статуса сервисов..."
    if command -v docker-compose &> /dev/null; then
        docker-compose ps
    else
        docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Health}}"
    fi
}

# Проверка healthcheck статуса
check_healthcheck_status() {
    log "Проверка healthcheck статуса..."

    local compose_cmd=$(get_compose_cmd)

    # Получаем список всех сервисов
    if command -v docker-compose &> /dev/null; then
        services=$(docker-compose ps --services)
    else
        services=$(docker compose ps --services)
    fi

    for service in $services; do
        # Проверяем health статус
        if command -v docker-compose &> /dev/null; then
            health_status=$(docker-compose ps "$service" | grep "$service" | awk '{print $4}' 2>/dev/null || echo "no-healthcheck")
        else
            health_status=$(docker compose ps "$service" --format "{{.Health}}" 2>/dev/null || echo "no-healthcheck")
        fi

        case $health_status in
            "healthy"|*"Up (healthy)"*)
                success "$service: здоров"
                ;;
            "unhealthy"|*"Up (unhealthy)"*)
                error "$service: нездоров"
                # Показываем логи для диагностики
                echo -e "\n${YELLOW}Последние логи $service:${NC}"
                $compose_cmd logs --tail=10 "$service"
                ;;
            "starting"|*"Up (health: starting)"*)
                warning "$service: запускается"
                ;;
            "no-healthcheck"|*"Up"*)
                warning "$service: healthcheck не настроен"
                ;;
            *)
                warning "$service: неизвестный статус ($health_status)"
                ;;
        esac
    done
}

# Тестирование HTTP endpoints
test_http_endpoints() {
    log "Тестирование HTTP endpoints..."

    declare -A endpoints=(
        ["http://localhost:80/health"]="Nginx health endpoint"
        ["http://localhost:9090/health"]="Auth сервис"
        ["http://localhost:11434/api/version"]="Ollama API"
        ["http://localhost:8080/health"]="OpenWebUI"
        ["http://localhost:5001/health"]="Docling"
        ["http://localhost:5050/voices"]="EdgeTTS"
        ["http://localhost:9998/tika"]="Tika"
    )

    for url in "${!endpoints[@]}"; do
        name="${endpoints[$url]}"

        if curl -sf --max-time 5 "$url" > /dev/null 2>&1; then
            success "$name: доступен ($url)"
        else
            error "$name: недоступен ($url)"
        fi
    done
}

# Генерация отчета
generate_healthcheck_report() {
    log "Генерация отчета healthcheck..."

    local compose_cmd=$(get_compose_cmd)
    report_file="healthcheck_report_$(date +%Y%m%d_%H%M%S).txt"

    {
        echo "=== ОТЧЕТ ТЕСТИРОВАНИЯ HEALTHCHECK ERNI-KI ==="
        echo "Дата: $(date)"
        echo "Хост: $(hostname)"
        echo ""

        echo "=== СТАТУС СЕРВИСОВ ==="
        if command -v docker-compose &> /dev/null; then
            docker-compose ps
        else
            docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Health}}"
        fi
        echo ""

        echo "=== HEALTHCHECK КОНФИГУРАЦИИ ==="
        $compose_cmd config | grep -A 15 "healthcheck:" | grep -E "(test|interval|timeout|retries|start_period):"
        echo ""

        echo "=== ЗАВИСИМОСТИ СЕРВИСОВ ==="
        $compose_cmd config | grep -A 5 "depends_on:" | grep -E "(depends_on|condition):"
        echo ""

        echo "=== ПОСЛЕДНИЕ ОШИБКИ ==="
        $compose_cmd logs --since=10m 2>/dev/null | grep -i "error\|fatal\|exception\|unhealthy" | tail -20

    } > "$report_file"

    success "Отчет сохранен в $report_file"
}

# Основная функция
main() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                ERNI-KI Healthcheck Test                     ║"
    echo "║              Тестирование конфигурации healthcheck          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_compose_config
    echo ""

    check_healthcheck_commands
    echo ""

    check_service_dependencies
    echo ""

    if [[ "$1" != "--config-only" ]]; then
        test_service_startup
        echo ""

        # Ждем дополнительное время для полной инициализации
        log "Ожидание полной инициализации (60 сек)..."
        sleep 60

        check_healthcheck_status
        echo ""

        test_http_endpoints
        echo ""
    fi

    # Опциональная генерация отчета
    if [[ "$1" == "--report" || "$2" == "--report" ]]; then
        generate_healthcheck_report
    fi

    log "Тестирование завершено!"
}

# Обработка аргументов командной строки
case "$1" in
    "--help"|"-h")
        echo "Использование: $0 [--config-only] [--report]"
        echo "  --config-only  Проверить только конфигурацию без запуска сервисов"
        echo "  --report       Сгенерировать подробный отчет"
        echo "  --help         Показать эту справку"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
