#!/bin/bash
# Автоматическое восстановление сервисов ERNI-KI
# Обнаружение и исправление типовых проблем

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Конфигурация
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/var/log/erni-ki-recovery.log"
MAX_RESTART_ATTEMPTS=3
HEALTH_CHECK_TIMEOUT=60
DEPENDENCY_WAIT_TIME=30

# Функции логирования
log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${BLUE}$message${NC}"
    echo "$message" >> "$LOG_FILE"
}

success() {
    local message="✅ $1"
    echo -e "${GREEN}$message${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1" >> "$LOG_FILE"
}

warning() {
    local message="⚠️  $1"
    echo -e "${YELLOW}$message${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE"
}

error() {
    local message="❌ $1"
    echo -e "${RED}$message${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE"
}

# Проверка состояния сервиса
check_service_health() {
    local service_name="$1"
    local max_attempts="${2:-3}"
    local attempt=1

    log "Проверка состояния сервиса: $service_name"

    while [[ $attempt -le $max_attempts ]]; do
        local status=$(docker-compose ps "$service_name" --format "{{.Status}}" 2>/dev/null || echo "not_found")

        case $status in
            *"Up"*"healthy"*)
                success "Сервис $service_name работает и здоров"
                return 0
                ;;
            *"Up"*)
                log "Сервис $service_name запущен, проверяем health check (попытка $attempt/$max_attempts)"
                sleep 10
                ;;
            *"Exit"*|*"Exited"*)
                warning "Сервис $service_name остановлен"
                return 1
                ;;
            *"Restarting"*)
                log "Сервис $service_name перезапускается, ожидаем (попытка $attempt/$max_attempts)"
                sleep 15
                ;;
            "not_found")
                error "Сервис $service_name не найден"
                return 2
                ;;
            *)
                warning "Сервис $service_name в неизвестном состоянии: $status"
                return 3
                ;;
        esac

        ((attempt++))
    done

    error "Сервис $service_name не прошел проверку здоровья за $max_attempts попыток"
    return 1
}

# Перезапуск сервиса с зависимостями
restart_service_with_dependencies() {
    local service_name="$1"
    local restart_dependencies="${2:-false}"

    log "Перезапуск сервиса: $service_name"

    # Получение зависимостей сервиса
    local dependencies=()
    case $service_name in
        "openwebui")
            dependencies=("db" "redis" "ollama" "searxng" "auth" "nginx")
            ;;
        "ollama")
            dependencies=("nvidia-container-runtime")
            ;;
        "searxng")
            dependencies=("redis")
            ;;
        "nginx")
            dependencies=("openwebui" "auth")
            ;;
        "auth")
            dependencies=("db")
            ;;
        "backrest")
            dependencies=("db" "redis")
            ;;
    esac

    # Проверка зависимостей
    if [[ "$restart_dependencies" == "true" ]]; then
        for dep in "${dependencies[@]}"; do
            if [[ "$dep" != "nvidia-container-runtime" ]]; then
                log "Проверка зависимости: $dep"
                if ! check_service_health "$dep" 1; then
                    warning "Зависимость $dep не здорова, перезапускаем"
                    restart_service_with_dependencies "$dep" false
                fi
            fi
        done
    fi

    # Graceful остановка сервиса
    log "Graceful остановка сервиса $service_name"
    if ! docker-compose stop "$service_name" --timeout=30; then
        warning "Graceful остановка не удалась, принудительная остановка"
        docker-compose kill "$service_name"
    fi

    # Ожидание полной остановки
    sleep 5

    # Запуск сервиса
    log "Запуск сервиса $service_name"
    if docker-compose up -d "$service_name"; then
        success "Сервис $service_name запущен"

        # Ожидание готовности
        log "Ожидание готовности сервиса $service_name"
        sleep $DEPENDENCY_WAIT_TIME

        # Проверка здоровья
        if check_service_health "$service_name" 5; then
            success "Сервис $service_name успешно восстановлен"
            return 0
        else
            error "Сервис $service_name не прошел проверку здоровья после перезапуска"
            return 1
        fi
    else
        error "Не удалось запустить сервис $service_name"
        return 1
    fi
}

# Очистка ресурсов Docker
cleanup_docker_resources() {
    log "Очистка ресурсов Docker"

    # Удаление остановленных контейнеров
    local stopped_containers=$(docker ps -a -q --filter "status=exited" 2>/dev/null || true)
    if [[ -n "$stopped_containers" ]]; then
        log "Удаление остановленных контейнеров"
        docker rm $stopped_containers || true
        success "Остановленные контейнеры удалены"
    fi

    # Удаление неиспользуемых образов
    log "Удаление неиспользуемых образов"
    docker image prune -f || true

    # Удаление неиспользуемых томов
    log "Удаление неиспользуемых томов"
    docker volume prune -f || true

    # Удаление неиспользуемых сетей
    log "Удаление неиспользуемых сетей"
    docker network prune -f || true

    success "Очистка ресурсов Docker завершена"
}

# Проверка и исправление проблем с GPU
fix_gpu_issues() {
    log "Проверка состояния GPU"

    # Проверка доступности nvidia-smi
    if ! command -v nvidia-smi &> /dev/null; then
        warning "nvidia-smi недоступен, пропускаем проверку GPU"
        return 0
    fi

    # Проверка состояния GPU
    if ! nvidia-smi &> /dev/null; then
        error "GPU недоступен"

        # Попытка перезапуска NVIDIA Container Runtime
        log "Перезапуск NVIDIA Container Runtime"
        sudo systemctl restart docker || true
        sleep 10

        # Повторная проверка
        if nvidia-smi &> /dev/null; then
            success "GPU восстановлен"
        else
            error "Не удалось восстановить GPU"
            return 1
        fi
    else
        success "GPU работает нормально"
    fi

    # Проверка температуры GPU
    local gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null || echo "0")
    if [[ $gpu_temp -gt 85 ]]; then
        warning "Высокая температура GPU: ${gpu_temp}°C"

        # Снижение нагрузки на GPU
        log "Временное снижение нагрузки на Ollama"
        docker-compose exec ollama pkill -STOP ollama || true
        sleep 30
        docker-compose exec ollama pkill -CONT ollama || true
    fi

    return 0
}

# Проверка и исправление проблем с базой данных
fix_database_issues() {
    log "Проверка состояния базы данных"

    # Проверка подключения к PostgreSQL
    if ! docker-compose exec -T db pg_isready -U postgres &> /dev/null; then
        warning "База данных недоступна"

        # Проверка логов базы данных
        local db_logs=$(docker-compose logs db --tail=50 2>/dev/null || echo "")
        if echo "$db_logs" | grep -i "corrupt\|error\|fatal" &> /dev/null; then
            error "Обнаружены ошибки в логах базы данных"

            # Попытка восстановления
            log "Попытка восстановления базы данных"
            restart_service_with_dependencies "db" false
        fi
    else
        success "База данных работает нормально"

        # Проверка количества соединений
        local connections=$(docker-compose exec -T db psql -U postgres -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | tr -d ' ' || echo "0")
        if [[ $connections -gt 80 ]]; then
            warning "Много активных соединений к базе данных: $connections"

            # Завершение длительных запросов
            log "Завершение длительных запросов"
            docker-compose exec -T db psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'active' AND query_start < now() - interval '5 minutes';" || true
        fi
    fi
}

# Проверка и исправление проблем с Redis
fix_redis_issues() {
    log "Проверка состояния Redis"

    # Проверка подключения к Redis
    if ! docker-compose exec -T redis redis-cli ping &> /dev/null; then
        warning "Redis недоступен"
        restart_service_with_dependencies "redis" false
    else
        success "Redis работает нормально"

        # Проверка использования памяти
        local memory_usage=$(docker-compose exec -T redis redis-cli info memory | grep "used_memory_human" | cut -d: -f2 | tr -d '\r' || echo "0B")
        log "Использование памяти Redis: $memory_usage"

        # Очистка кеша при высоком использовании
        local memory_percent=$(docker-compose exec -T redis redis-cli info memory | grep "used_memory_rss_human" | cut -d: -f2 | tr -d '\r' | sed 's/[^0-9]//g' || echo "0")
        if [[ $memory_percent -gt 500 ]]; then  # Более 500MB
            warning "Высокое использование памяти Redis"
            log "Очистка кеша Redis"
            docker-compose exec -T redis redis-cli flushdb || true
        fi
    fi
}

# Проверка дискового пространства
check_disk_space() {
    log "Проверка дискового пространства"

    # Проверка основного диска
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    log "Использование диска /: ${disk_usage}%"

    if [[ $disk_usage -gt 90 ]]; then
        error "Критически мало места на диске: ${disk_usage}%"

        # Очистка логов Docker
        log "Очистка логов Docker"
        docker system prune -f --volumes || true

        # Очистка старых архивов
        log "Очистка старых архивов логов"
        find "$PROJECT_ROOT/.config-backup/logs" -name "*.gz" -mtime +7 -delete 2>/dev/null || true

        # Повторная проверка
        disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
        if [[ $disk_usage -gt 85 ]]; then
            warning "Место на диске все еще критично: ${disk_usage}%"
        else
            success "Место на диске освобождено: ${disk_usage}%"
        fi
    elif [[ $disk_usage -gt 80 ]]; then
        warning "Мало места на диске: ${disk_usage}%"
    else
        success "Достаточно места на диске: ${disk_usage}%"
    fi
}

# Автоматическое восстановление всех сервисов
auto_recovery() {
    log "Запуск автоматического восстановления ERNI-KI"

    # Проверка системных ресурсов
    check_disk_space
    echo ""

    # Очистка ресурсов Docker
    cleanup_docker_resources
    echo ""

    # Исправление проблем с GPU
    fix_gpu_issues
    echo ""

    # Исправление проблем с базой данных
    fix_database_issues
    echo ""

    # Исправление проблем с Redis
    fix_redis_issues
    echo ""

    # Проверка критических сервисов
    local critical_services=("db" "redis" "nginx" "auth")
    for service in "${critical_services[@]}"; do
        log "Проверка критического сервиса: $service"
        if ! check_service_health "$service" 2; then
            warning "Критический сервис $service нездоров, перезапускаем"
            restart_service_with_dependencies "$service" false
        fi
        echo ""
    done

    # Проверка AI сервисов
    local ai_services=("ollama" "openwebui" "searxng")
    for service in "${ai_services[@]}"; do
        log "Проверка AI сервиса: $service"
        if ! check_service_health "$service" 2; then
            warning "AI сервис $service нездоров, перезапускаем"
            restart_service_with_dependencies "$service" true
        fi
        echo ""
    done

    # Финальная проверка всех сервисов
    log "Финальная проверка всех сервисов"
    local all_services=("db" "redis" "nginx" "auth" "ollama" "openwebui" "searxng" "docling" "edgetts" "tika" "mcposerver" "cloudflared" "watchtower" "backrest")
    local unhealthy_count=0

    for service in "${all_services[@]}"; do
        if ! check_service_health "$service" 1; then
            ((unhealthy_count++))
        fi
    done

    if [[ $unhealthy_count -eq 0 ]]; then
        success "Все сервисы здоровы! Автоматическое восстановление завершено успешно"
    else
        warning "Обнаружено $unhealthy_count нездоровых сервисов после восстановления"
        warning "Требуется ручное вмешательство"
    fi
}

# Основная функция
main() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                ERNI-KI Automated Recovery                   ║"
    echo "║              Автоматическое восстановление                  ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Переход в рабочую директорию
    cd "$PROJECT_ROOT"

    # Выполнение восстановления
    auto_recovery
}

# Обработка аргументов командной строки
case "${1:-}" in
    --service)
        if [[ -n "${2:-}" ]]; then
            log "Восстановление конкретного сервиса: $2"
            cd "$PROJECT_ROOT"
            restart_service_with_dependencies "$2" true
        else
            error "Укажите имя сервиса для восстановления"
            exit 1
        fi
        ;;
    --gpu)
        log "Исправление проблем с GPU"
        fix_gpu_issues
        ;;
    --database)
        log "Исправление проблем с базой данных"
        cd "$PROJECT_ROOT"
        fix_database_issues
        ;;
    --redis)
        log "Исправление проблем с Redis"
        cd "$PROJECT_ROOT"
        fix_redis_issues
        ;;
    --cleanup)
        log "Очистка ресурсов Docker"
        cleanup_docker_resources
        ;;
    --disk)
        log "Проверка дискового пространства"
        check_disk_space
        ;;
    *)
        main
        ;;
esac
