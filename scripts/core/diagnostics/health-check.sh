#!/bin/bash
# Скрипт проверки состояния всех сервисов ERNI-KI
# Автор: Альтэон Шульц (Tech Lead)

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция логирования
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

# Проверка Docker Compose
check_docker_compose() {
    log "Проверка Docker Compose..."

    if ! command -v docker &> /dev/null; then
        error "Docker не установлен"
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose не установлен"
        exit 1
    fi

    success "Docker и Docker Compose доступны"
}

# Проверка состояния сервисов
check_services_status() {
    log "Проверка состояния сервисов..."

    services=("auth" "db" "redis" "ollama" "nginx" "openwebui" "searxng" "docling" "edgetts" "tika" "mcposerver")

    for service in "${services[@]}"; do
        status=$(docker-compose ps "$service" 2>/dev/null | grep "$service" | awk '{print $4}' || echo "not_found")

        case $status in
            *"Up"*)
                success "$service: работает"
                ;;
            *"Exit"*)
                error "$service: остановлен"
                ;;
            *"Restarting"*)
                warning "$service: перезапускается"
                ;;
            "not_found")
                warning "$service: не найден"
                ;;
            *)
                warning "$service: неизвестное состояние ($status)"
                ;;
        esac
    done
}

# Проверка HTTP endpoints
check_http_endpoints() {
    log "Проверка HTTP endpoints..."

    declare -A endpoints=(
        ["http://localhost:9090/health"]="Auth сервис"
        ["http://localhost:11434/api/version"]="Ollama API"
        ["http://localhost:80/health"]="Nginx proxy"
        ["http://localhost:8080/health"]="OpenWebUI"
        ["http://localhost:5001/health"]="Docling"
        ["http://localhost:5050/voices"]="EdgeTTS"
        ["http://localhost:9998/tika"]="Tika"
        ["http://localhost:8080/"]="SearXNG"
    )

    for url in "${!endpoints[@]}"; do
        name="${endpoints[$url]}"

        if curl -sf "$url" > /dev/null 2>&1; then
            success "$name: доступен ($url)"
        else
            error "$name: недоступен ($url)"
        fi
    done
}

# Проверка базы данных
check_database() {
    log "Проверка базы данных..."

    if docker-compose exec -T db pg_isready -d openwebui -U postgres > /dev/null 2>&1; then
        success "PostgreSQL: подключение успешно"

        # Проверка количества таблиц
        table_count=$(docker-compose exec -T db psql -U postgres -d openwebui -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ')

        if [[ "$table_count" =~ ^[0-9]+$ ]] && [ "$table_count" -gt 0 ]; then
            success "База данных: $table_count таблиц найдено"
        else
            warning "База данных: таблицы не найдены или не инициализированы"
        fi
    else
        error "PostgreSQL: подключение неудачно"
    fi
}

# Проверка Redis
check_redis() {
    log "Проверка Redis..."

    if docker-compose exec -T redis redis-cli ping 2>/dev/null | grep -q "PONG"; then
        success "Redis: подключение успешно"

        # Проверка использования памяти
        memory_usage=$(docker-compose exec -T redis redis-cli info memory 2>/dev/null | grep "used_memory_human" | cut -d: -f2 | tr -d '\r')
        success "Redis: использование памяти $memory_usage"
    else
        error "Redis: подключение неудачно"
    fi
}

# Проверка Ollama моделей
check_ollama_models() {
    log "Проверка моделей Ollama..."

    if docker-compose exec -T ollama ollama list > /dev/null 2>&1; then
        models=$(docker-compose exec -T ollama ollama list 2>/dev/null | tail -n +2 | wc -l)

        if [ "$models" -gt 0 ]; then
            success "Ollama: $models моделей загружено"
            docker-compose exec -T ollama ollama list 2>/dev/null | tail -n +2 | while read -r line; do
                model_name=$(echo "$line" | awk '{print $1}')
                model_size=$(echo "$line" | awk '{print $2}')
                success "  - $model_name ($model_size)"
            done
        else
            warning "Ollama: модели не загружены"
        fi
    else
        error "Ollama: недоступен"
    fi
}

# Проверка использования ресурсов
check_resource_usage() {
    log "Проверка использования ресурсов..."

    # Проверка дискового пространства
    disk_usage=$(df -h . | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$disk_usage" -lt 80 ]; then
        success "Диск: использовано ${disk_usage}%"
    elif [ "$disk_usage" -lt 90 ]; then
        warning "Диск: использовано ${disk_usage}% (рекомендуется очистка)"
    else
        error "Диск: использовано ${disk_usage}% (критично!)"
    fi

    # Проверка памяти Docker
    if command -v docker &> /dev/null; then
        docker_memory=$(docker stats --no-stream --format "{{.MemUsage}}" 2>/dev/null | head -5 | awk -F'/' '{sum+=$1} END {print sum}' || echo "0")
        success "Docker: использование памяти контейнерами"
    fi
}

# Проверка логов на ошибки
check_error_logs() {
    log "Проверка логов на ошибки..."

    error_count=$(docker-compose logs --since=1h 2>/dev/null | grep -i "error\|fatal\|exception" | wc -l)

    if [ "$error_count" -eq 0 ]; then
        success "Логи: ошибок за последний час не найдено"
    elif [ "$error_count" -lt 5 ]; then
        warning "Логи: найдено $error_count ошибок за последний час"
    else
        error "Логи: найдено $error_count ошибок за последний час (требует внимания)"
    fi
}

# Генерация отчета
generate_report() {
    log "Генерация отчета..."

    report_file="health_report_$(date +%Y%m%d_%H%M%S).txt"

    {
        echo "=== ОТЧЕТ О СОСТОЯНИИ ERNI-KI ==="
        echo "Дата: $(date)"
        echo "Хост: $(hostname)"
        echo ""

        echo "=== СОСТОЯНИЕ СЕРВИСОВ ==="
        docker-compose ps
        echo ""

        echo "=== ИСПОЛЬЗОВАНИЕ РЕСУРСОВ ==="
        docker stats --no-stream
        echo ""

        echo "=== ПОСЛЕДНИЕ ОШИБКИ ==="
        docker-compose logs --since=1h 2>/dev/null | grep -i "error\|fatal\|exception" | tail -10
        echo ""

        echo "=== МОДЕЛИ OLLAMA ==="
        docker-compose exec -T ollama ollama list 2>/dev/null || echo "Ollama недоступен"
        echo ""

    } > "$report_file"

    success "Отчет сохранен в $report_file"
}

# Основная функция
main() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    ERNI-KI Health Check                     ║"
    echo "║                  Проверка состояния системы                 ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_docker_compose
    echo ""

    check_services_status
    echo ""

    check_http_endpoints
    echo ""

    check_database
    echo ""

    check_redis
    echo ""

    check_ollama_models
    echo ""

    check_resource_usage
    echo ""

    check_error_logs
    echo ""

    # Опциональная генерация отчета
    if [[ "$1" == "--report" ]]; then
        generate_report
    fi

    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    Проверка завершена                       ║"
    echo "║         Для подробного отчета: ./health_check.sh --report   ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Запуск скрипта
main "$@"
