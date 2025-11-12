#!/bin/bash
# Тестирование совместимости контейнеров ERNI-KI
# Автор: Альтэон Шульц (Tech Lead)

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Функции логирования
log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }
info() { echo -e "${CYAN}ℹ️  $1${NC}"; }
section() { echo -e "${PURPLE}🔍 $1${NC}"; }

# Проверка версий Docker и docker-compose
check_docker_versions() {
    section "Проверка версий Docker и Docker Compose"

    # Проверка Docker
    if command -v docker &> /dev/null; then
        local docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        success "Docker версия: $docker_version"

        # Проверка минимальной версии (20.10+)
        local major=$(echo "$docker_version" | cut -d. -f1)
        local minor=$(echo "$docker_version" | cut -d. -f2)

        if [ "$major" -gt 20 ] || ([ "$major" -eq 20 ] && [ "$minor" -ge 10 ]); then
            success "Docker версия совместима с ERNI-KI"
        else
            warning "Docker версия может быть устаревшей (рекомендуется 20.10+)"
        fi

        # Проверка Docker daemon
        if docker info &> /dev/null; then
            success "Docker daemon работает"

            # Информация о Docker
            local docker_root=$(docker info --format '{{.DockerRootDir}}')
            local storage_driver=$(docker info --format '{{.Driver}}')
            success "Docker root: $docker_root"
            success "Storage driver: $storage_driver"
        else
            error "Docker daemon не работает"
            return 1
        fi
    else
        error "Docker не установлен"
        return 1
    fi

    # Проверка docker-compose
    if command -v docker-compose &> /dev/null; then
        local compose_version=$(docker-compose --version | awk '{print $3}' | sed 's/,//')
        success "Docker Compose версия: $compose_version"

        # Проверка минимальной версии (1.29+)
        local major=$(echo "$compose_version" | cut -d. -f1)
        local minor=$(echo "$compose_version" | cut -d. -f2)

        if [ "$major" -gt 1 ] || ([ "$major" -eq 1 ] && [ "$minor" -ge 29 ]); then
            success "Docker Compose версия совместима"
        else
            warning "Docker Compose версия может быть устаревшей (рекомендуется 1.29+)"
        fi
    else
        error "Docker Compose не установлен"
        return 1
    fi

    # Проверка docker compose (v2)
    if docker compose version &> /dev/null; then
        local compose_v2=$(docker compose version --short)
        info "Docker Compose v2 также доступен: $compose_v2"
    fi

    echo ""
}

# Проверка конфигурации Docker Compose
check_compose_config() {
    section "Проверка конфигурации Docker Compose"

    if [ -f "compose.yml" ]; then
        success "Файл compose.yml найден"

        # Валидация конфигурации
        if docker-compose config &> /dev/null; then
            success "Конфигурация Docker Compose валидна"

            # Подсчет сервисов
            local services_count=$(docker-compose config --services | wc -l)
            success "Количество сервисов: $services_count"

            # Список сервисов
            info "Сервисы в конфигурации:"
            docker-compose config --services | while read service; do
                echo "  • $service"
            done
        else
            error "Ошибка в конфигурации Docker Compose"
            docker-compose config
            return 1
        fi
    else
        error "Файл compose.yml не найден"
        return 1
    fi
    echo ""
}

# Проверка образов Docker
check_docker_images() {
    section "Проверка доступности Docker образов"

    # Получение списка образов из compose.yml
    local images=$(docker-compose config | grep "image:" | awk '{print $2}' | sort -u)

    echo "$images" | while read image; do
        if [ -n "$image" ]; then
            log "Проверка образа: $image"

            # Проверка наличия образа локально
            if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^$image$"; then
                success "Образ $image доступен локально"
            else
                info "Образ $image отсутствует локально"

                # Попытка загрузки образа
                log "Попытка загрузки образа $image..."
                if docker pull "$image" &> /dev/null; then
                    success "Образ $image успешно загружен"
                else
                    warning "Не удалось загрузить образ $image"
                fi
            fi
        fi
    done
    echo ""
}

# Тестирование запуска сервисов
test_services_startup() {
    section "Тестирование запуска сервисов"

    # Список критичных сервисов в порядке запуска
    local critical_services=("db" "redis" "auth" "ollama" "nginx" "openwebui")
    local optional_services=("searxng" "edgetts" "tika" "mcposerver")

    # Остановка всех сервисов для чистого теста
    log "Остановка всех сервисов для чистого теста..."
    docker-compose down &> /dev/null || true

    # Тестирование критичных сервисов
    for service in "${critical_services[@]}"; do
        log "Тестирование запуска сервиса: $service"

        if docker-compose up -d "$service" &> /dev/null; then
            sleep 5

            # Проверка статуса
            local status=$(docker-compose ps "$service" --format "{{.State}}" 2>/dev/null || echo "unknown")
            if echo "$status" | grep -q "Up"; then
                success "Сервис $service запущен успешно"
            else
                warning "Сервис $service имеет проблемы: $status"

                # Показать логи для диагностики
                echo "Последние логи $service:"
                docker-compose logs --tail=10 "$service" 2>/dev/null || echo "Логи недоступны"
            fi
        else
            error "Не удалось запустить сервис $service"
        fi
    done

    # Тестирование опциональных сервисов
    log "Тестирование опциональных сервисов..."
    for service in "${optional_services[@]}"; do
        if docker-compose up -d "$service" &> /dev/null; then
            sleep 3
            local status=$(docker-compose ps "$service" --format "{{.State}}" 2>/dev/null || echo "unknown")
            if echo "$status" | grep -q "Up"; then
                success "Опциональный сервис $service работает"
            else
                info "Опциональный сервис $service: $status"
            fi
        else
            info "Опциональный сервис $service не запустился"
        fi
    done
    echo ""
}

# Проверка межсервисной коммуникации
test_inter_service_communication() {
    section "Тестирование межсервисной коммуникации"

    # Проверка подключения к базе данных
    log "Проверка подключения к PostgreSQL..."
    if docker-compose exec -T db pg_isready -U postgres &> /dev/null; then
        success "PostgreSQL доступен"

        # Проверка создания подключения
        if docker-compose exec -T db psql -U postgres -d openwebui -c "SELECT 1;" &> /dev/null; then
            success "Подключение к базе данных работает"
        else
            warning "Проблемы с подключением к базе данных"
        fi
    else
        error "PostgreSQL недоступен"
    fi

    # Проверка Redis
    log "Проверка подключения к Redis..."
    if docker-compose exec -T redis redis-cli ping 2>/dev/null | grep -q "PONG"; then
        success "Redis доступен"
    else
        error "Redis недоступен"
    fi

    # Проверка Ollama API
    log "Проверка Ollama API..."
    if curl -sf http://localhost:11434/api/version &> /dev/null; then
        success "Ollama API доступен"

        # Проверка загруженных моделей
        local models=$(docker-compose exec -T ollama ollama list 2>/dev/null | tail -n +2 | wc -l)
        if [ "$models" -gt 0 ]; then
            success "Ollama: $models моделей загружено"
        else
            warning "Ollama: модели не загружены"
        fi
    else
        error "Ollama API недоступен"
    fi

    # Проверка Auth сервиса
    log "Проверка Auth API..."
    if curl -sf http://localhost:9090/health &> /dev/null; then
        success "Auth API доступен"
    else
        error "Auth API недоступен"
    fi

    # Проверка Nginx
    log "Проверка Nginx..."
    if curl -sf http://localhost &> /dev/null; then
        success "Nginx доступен"
    else
        error "Nginx недоступен"
    fi

    # Проверка OpenWebUI
    log "Проверка OpenWebUI..."
    if curl -sf http://localhost:8080 &> /dev/null; then
        success "OpenWebUI доступен"
    else
        warning "OpenWebUI может быть недоступен"
    fi
    echo ""
}

# Анализ использования ресурсов контейнерами
analyze_resource_usage() {
    section "Анализ использования ресурсов контейнерами"

    # Получение статистики контейнеров
    log "Сбор статистики использования ресурсов..."

    # Заголовок таблицы
    printf "%-20s %-10s %-15s %-15s %-10s\n" "КОНТЕЙНЕР" "CPU %" "ПАМЯТЬ" "СЕТЬ I/O" "ДИСК I/O"
    echo "────────────────────────────────────────────────────────────────────────"

    # Получение статистики для каждого контейнера
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" | tail -n +2 | while read line; do
        echo "$line"
    done

    echo ""

    # Анализ общего использования
    local total_containers=$(docker ps -q | wc -l)
    success "Всего запущенных контейнеров: $total_containers"

    # Проверка лимитов памяти
    log "Проверка лимитов ресурсов..."
    docker-compose config | grep -A 5 -B 5 "mem_limit\|cpus\|memory" | grep -v "^--$" || info "Лимиты ресурсов не настроены"

    echo ""
}

# Проверка сетевой конфигурации
check_network_configuration() {
    section "Проверка сетевой конфигурации Docker"

    # Список Docker сетей
    success "Docker сети:"
    docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}"

    # Проверка сети проекта
    local project_network=$(docker-compose config | grep -A 10 "networks:" | grep -v "networks:" | head -1 | awk '{print $1}' | sed 's/://')
    if [ -n "$project_network" ]; then
        info "Сеть проекта: $project_network"

        # Детали сети
        docker network inspect "$project_network" &> /dev/null && success "Сеть проекта настроена корректно" || warning "Проблемы с сетью проекта"
    fi

    # Проверка портов
    log "Проверка открытых портов..."
    netstat -tuln 2>/dev/null | grep -E ":(80|5432|6379|8080|9090|11434|5001|5050|9998|8000) " | while read line; do
        local port=$(echo "$line" | awk '{print $4}' | cut -d: -f2)
        success "Порт $port открыт"
    done

    echo ""
}

# Генерация отчета совместимости
generate_compatibility_report() {
    section "Отчет совместимости контейнеров"

    local score=0
    local max_score=8
    local issues=()
    local recommendations=()

    # Проверка Docker
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        score=$((score + 2))
        success "Docker: Работает корректно"
    else
        error "Docker: Проблемы с установкой или запуском"
        issues+=("Docker не работает корректно")
    fi

    # Проверка docker-compose
    if command -v docker-compose &> /dev/null && docker-compose config &> /dev/null; then
        score=$((score + 1))
        success "Docker Compose: Конфигурация валидна"
    else
        error "Docker Compose: Проблемы с конфигурацией"
        issues+=("Проблемы с Docker Compose")
    fi

    # Проверка запущенных сервисов
    local running_services=$(docker-compose ps --services --filter "status=running" | wc -l)
    local total_services=$(docker-compose ps --services | wc -l)

    if [ "$running_services" -ge 8 ]; then
        score=$((score + 2))
        success "Сервисы: $running_services/$total_services запущено"
    elif [ "$running_services" -ge 5 ]; then
        score=$((score + 1))
        warning "Сервисы: $running_services/$total_services запущено"
        recommendations+=("Проверьте незапущенные сервисы")
    else
        error "Сервисы: Критически мало запущенных сервисов"
        issues+=("Большинство сервисов не запущено")
    fi

    # Проверка API endpoints
    local working_apis=0
    local apis=("http://localhost" "http://localhost:9090/health" "http://localhost:11434/api/version")

    for api in "${apis[@]}"; do
        if curl -sf "$api" &> /dev/null; then
            working_apis=$((working_apis + 1))
        fi
    done

    if [ "$working_apis" -eq 3 ]; then
        score=$((score + 2))
        success "API: Все основные API доступны"
    elif [ "$working_apis" -ge 2 ]; then
        score=$((score + 1))
        warning "API: Некоторые API недоступны"
        recommendations+=("Проверьте недоступные API")
    else
        error "API: Критические проблемы с API"
        issues+=("Основные API недоступны")
    fi

    # Проверка межсервисной коммуникации
    if docker-compose exec -T db pg_isready &> /dev/null && docker-compose exec -T redis redis-cli ping &> /dev/null; then
        score=$((score + 1))
        success "Коммуникация: Межсервисная связь работает"
    else
        warning "Коммуникация: Проблемы с межсервисной связью"
        recommendations+=("Проверьте сетевые подключения между сервисами")
    fi

    # Итоговая оценка
    local percentage=$((score * 100 / max_score))
    echo ""

    if [ "$percentage" -ge 90 ]; then
        success "ИТОГОВАЯ ОЦЕНКА СОВМЕСТИМОСТИ: ${percentage}% - Отлично"
    elif [ "$percentage" -ge 70 ]; then
        info "ИТОГОВАЯ ОЦЕНКА СОВМЕСТИМОСТИ: ${percentage}% - Хорошо"
    elif [ "$percentage" -ge 50 ]; then
        warning "ИТОГОВАЯ ОЦЕНКА СОВМЕСТИМОСТИ: ${percentage}% - Удовлетворительно"
    else
        error "ИТОГОВАЯ ОЦЕНКА СОВМЕСТИМОСТИ: ${percentage}% - Неудовлетворительно"
    fi

    # Проблемы
    if [ ${#issues[@]} -gt 0 ]; then
        echo ""
        error "Обнаруженные проблемы:"
        for issue in "${issues[@]}"; do
            echo "  • $issue"
        done
    fi

    # Рекомендации
    if [ ${#recommendations[@]} -gt 0 ]; then
        echo ""
        warning "Рекомендации:"
        for rec in "${recommendations[@]}"; do
            echo "  • $rec"
        done
    fi
}

# Основная функция
main() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              Container Compatibility Test                   ║"
    echo "║           Тестирование совместимости контейнеров            ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_docker_versions
    check_compose_config
    check_docker_images
    test_services_startup
    test_inter_service_communication
    analyze_resource_usage
    check_network_configuration
    generate_compatibility_report

    echo ""
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                 Тестирование завершено                      ║"
    echo "║        Результаты сохранены в compatibility_report.txt      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Запуск тестирования
main "$@" | tee compatibility_report.txt
