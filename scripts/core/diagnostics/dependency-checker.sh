#!/bin/bash
# Проверка зависимостей сервисов ERNI-KI
# Анализ и валидация dependency chains

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
LOG_FILE="/var/log/erni-ki-dependency-check.log"

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

# Определение зависимостей сервисов
declare -A SERVICE_DEPENDENCIES
SERVICE_DEPENDENCIES=(
    ["watchtower"]=""
    ["db"]="watchtower"
    ["redis"]="watchtower"
    ["auth"]="db"
    ["ollama"]="watchtower"
    ["searxng"]="redis"
    ["edgetts"]="watchtower"
    ["tika"]="watchtower"
    ["mcposerver"]="watchtower"
    ["nginx"]="auth"
    ["openwebui"]="auth db redis ollama searxng nginx edgetts mcposerver tika"
    ["cloudflared"]="nginx"
    ["backrest"]="db redis"
)

# Определение критичности сервисов
declare -A SERVICE_CRITICALITY
SERVICE_CRITICALITY=(
    ["db"]="critical"
    ["redis"]="critical"
    ["nginx"]="critical"
    ["auth"]="critical"
    ["ollama"]="high"
    ["openwebui"]="high"
    ["searxng"]="medium"
    ["cloudflared"]="medium"
    ["backrest"]="medium"
    ["edgetts"]="low"
    ["tika"]="low"
    ["mcposerver"]="low"
    ["watchtower"]="low"
)

# Проверка состояния сервиса
check_service_status() {
    local service_name="$1"
    local status=$(docker-compose ps "$service_name" --format "{{.Status}}" 2>/dev/null || echo "not_found")

    case $status in
        *"Up"*"healthy"*)
            echo "healthy"
            ;;
        *"Up"*)
            echo "running"
            ;;
        *"Exit"*|*"Exited"*)
            echo "stopped"
            ;;
        *"Restarting"*)
            echo "restarting"
            ;;
        "not_found")
            echo "not_found"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Проверка зависимостей для конкретного сервиса
check_service_dependencies() {
    local service_name="$1"
    local dependencies="${SERVICE_DEPENDENCIES[$service_name]:-}"
    local all_healthy=true

    if [[ -z "$dependencies" ]]; then
        success "Сервис $service_name не имеет зависимостей"
        return 0
    fi

    log "Проверка зависимостей для сервиса: $service_name"

    for dep in $dependencies; do
        local dep_status=$(check_service_status "$dep")
        local criticality="${SERVICE_CRITICALITY[$dep]:-low}"

        case $dep_status in
            "healthy")
                success "  ✓ $dep: здоров ($criticality)"
                ;;
            "running")
                if [[ "$criticality" == "critical" ]]; then
                    warning "  ⚠ $dep: запущен но не здоров ($criticality)"
                    all_healthy=false
                else
                    success "  ✓ $dep: запущен ($criticality)"
                fi
                ;;
            "stopped")
                error "  ✗ $dep: остановлен ($criticality)"
                all_healthy=false
                ;;
            "restarting")
                warning "  ⟳ $dep: перезапускается ($criticality)"
                all_healthy=false
                ;;
            "not_found")
                error "  ✗ $dep: не найден ($criticality)"
                all_healthy=false
                ;;
            *)
                warning "  ? $dep: неизвестное состояние ($criticality)"
                all_healthy=false
                ;;
        esac
    done

    if [[ "$all_healthy" == "true" ]]; then
        success "Все зависимости для $service_name готовы"
        return 0
    else
        error "Некоторые зависимости для $service_name не готовы"
        return 1
    fi
}

# Построение графа зависимостей
build_dependency_graph() {
    log "Построение графа зависимостей"

    echo "digraph ERNI_KI_Dependencies {" > /tmp/dependencies.dot
    echo "  rankdir=TB;" >> /tmp/dependencies.dot
    echo "  node [shape=box];" >> /tmp/dependencies.dot
    echo "" >> /tmp/dependencies.dot

    # Добавление узлов с цветами по критичности
    for service in "${!SERVICE_CRITICALITY[@]}"; do
        local criticality="${SERVICE_CRITICALITY[$service]}"
        local color=""

        case $criticality in
            "critical") color="red" ;;
            "high") color="orange" ;;
            "medium") color="yellow" ;;
            "low") color="lightblue" ;;
        esac

        echo "  $service [fillcolor=$color, style=filled];" >> /tmp/dependencies.dot
    done

    echo "" >> /tmp/dependencies.dot

    # Добавление связей
    for service in "${!SERVICE_DEPENDENCIES[@]}"; do
        local dependencies="${SERVICE_DEPENDENCIES[$service]}"

        if [[ -n "$dependencies" ]]; then
            for dep in $dependencies; do
                echo "  $dep -> $service;" >> /tmp/dependencies.dot
            done
        fi
    done

    echo "}" >> /tmp/dependencies.dot

    success "Граф зависимостей сохранен в /tmp/dependencies.dot"

    # Попытка создать PNG если доступен graphviz
    if command -v dot &> /dev/null; then
        if dot -Tpng /tmp/dependencies.dot -o "$PROJECT_ROOT/.config-backup/dependency-graph.png" 2>/dev/null; then
            success "Граф зависимостей сохранен как PNG: $PROJECT_ROOT/.config-backup/dependency-graph.png"
        fi
    fi
}

# Анализ циклических зависимостей
check_circular_dependencies() {
    log "Проверка циклических зависимостей"

    local visited=()
    local recursion_stack=()
    local has_cycle=false

    # Функция DFS для поиска циклов
    dfs_check_cycle() {
        local node="$1"

        # Добавляем в стек рекурсии
        recursion_stack+=("$node")

        # Получаем зависимости
        local dependencies="${SERVICE_DEPENDENCIES[$node]:-}"

        for dep in $dependencies; do
            # Проверяем, есть ли узел в стеке рекурсии
            for stack_node in "${recursion_stack[@]}"; do
                if [[ "$stack_node" == "$dep" ]]; then
                    error "Обнаружена циклическая зависимость: $dep -> ... -> $node -> $dep"
                    has_cycle=true
                    return 1
                fi
            done

            # Рекурсивно проверяем зависимости
            if [[ -n "${SERVICE_DEPENDENCIES[$dep]:-}" ]]; then
                dfs_check_cycle "$dep"
            fi
        done

        # Удаляем из стека рекурсии
        recursion_stack=("${recursion_stack[@]/$node}")
    }

    # Проверяем каждый сервис
    for service in "${!SERVICE_DEPENDENCIES[@]}"; do
        recursion_stack=()
        dfs_check_cycle "$service"
    done

    if [[ "$has_cycle" == "false" ]]; then
        success "Циклические зависимости не обнаружены"
        return 0
    else
        error "Обнаружены циклические зависимости!"
        return 1
    fi
}

# Определение порядка запуска
calculate_startup_order() {
    log "Вычисление порядка запуска сервисов"

    local startup_order=()
    local processed=()

    # Функция для добавления сервиса в порядок запуска
    add_to_startup_order() {
        local service="$1"

        # Проверяем, не обработан ли уже
        for proc in "${processed[@]}"; do
            if [[ "$proc" == "$service" ]]; then
                return 0
            fi
        done

        # Сначала добавляем все зависимости
        local dependencies="${SERVICE_DEPENDENCIES[$service]:-}"
        for dep in $dependencies; do
            add_to_startup_order "$dep"
        done

        # Затем добавляем сам сервис
        startup_order+=("$service")
        processed+=("$service")
    }

    # Обрабатываем все сервисы
    for service in "${!SERVICE_DEPENDENCIES[@]}"; do
        add_to_startup_order "$service"
    done

    log "Рекомендуемый порядок запуска:"
    local order_num=1
    for service in "${startup_order[@]}"; do
        local criticality="${SERVICE_CRITICALITY[$service]:-low}"
        log "  $order_num. $service ($criticality)"
        ((order_num++))
    done

    # Сохранение порядка в файл
    printf '%s\n' "${startup_order[@]}" > "$PROJECT_ROOT/.config-backup/startup-order.txt"
    success "Порядок запуска сохранен в $PROJECT_ROOT/.config-backup/startup-order.txt"
}

# Определение порядка остановки
calculate_shutdown_order() {
    log "Вычисление порядка остановки сервисов"

    # Читаем порядок запуска и обращаем его
    if [[ -f "$PROJECT_ROOT/.config-backup/startup-order.txt" ]]; then
        local shutdown_order=()
        while IFS= read -r line; do
            shutdown_order=("$line" "${shutdown_order[@]}")
        done < "$PROJECT_ROOT/.config-backup/startup-order.txt"

        log "Рекомендуемый порядок остановки:"
        local order_num=1
        for service in "${shutdown_order[@]}"; do
            local criticality="${SERVICE_CRITICALITY[$service]:-low}"
            log "  $order_num. $service ($criticality)"
            ((order_num++))
        done

        # Сохранение порядка в файл
        printf '%s\n' "${shutdown_order[@]}" > "$PROJECT_ROOT/.config-backup/shutdown-order.txt"
        success "Порядок остановки сохранен в $PROJECT_ROOT/.config-backup/shutdown-order.txt"
    else
        error "Файл порядка запуска не найден"
        return 1
    fi
}

# Проверка всех зависимостей
check_all_dependencies() {
    log "Проверка зависимостей всех сервисов"

    local failed_services=()

    for service in "${!SERVICE_DEPENDENCIES[@]}"; do
        echo ""
        if ! check_service_dependencies "$service"; then
            failed_services+=("$service")
        fi
    done

    echo ""
    if [[ ${#failed_services[@]} -eq 0 ]]; then
        success "Все зависимости сервисов выполнены"
        return 0
    else
        error "Сервисы с невыполненными зависимостями: ${failed_services[*]}"
        return 1
    fi
}

# Генерация отчета о зависимостях
generate_dependency_report() {
    log "Генерация отчета о зависимостях"

    local report_file="$PROJECT_ROOT/.config-backup/dependency-report-$(date +%Y%m%d_%H%M%S).txt"

    {
        echo "=== ОТЧЕТ О ЗАВИСИМОСТЯХ ERNI-KI ==="
        echo "Дата: $(date)"
        echo "Хост: $(hostname)"
        echo ""

        echo "=== ГРАФ ЗАВИСИМОСТЕЙ ==="
        for service in "${!SERVICE_DEPENDENCIES[@]}"; do
            local dependencies="${SERVICE_DEPENDENCIES[$service]:-}"
            local criticality="${SERVICE_CRITICALITY[$service]:-low}"

            if [[ -n "$dependencies" ]]; then
                echo "$service ($criticality) зависит от: $dependencies"
            else
                echo "$service ($criticality) не имеет зависимостей"
            fi
        done
        echo ""

        echo "=== СОСТОЯНИЕ СЕРВИСОВ ==="
        for service in "${!SERVICE_DEPENDENCIES[@]}"; do
            local status=$(check_service_status "$service")
            local criticality="${SERVICE_CRITICALITY[$service]:-low}"
            echo "$service: $status ($criticality)"
        done
        echo ""

        echo "=== ПОРЯДОК ЗАПУСКА ==="
        if [[ -f "$PROJECT_ROOT/.config-backup/startup-order.txt" ]]; then
            cat "$PROJECT_ROOT/.config-backup/startup-order.txt"
        else
            echo "Порядок запуска не вычислен"
        fi
        echo ""

        echo "=== ПОРЯДОК ОСТАНОВКИ ==="
        if [[ -f "$PROJECT_ROOT/.config-backup/shutdown-order.txt" ]]; then
            cat "$PROJECT_ROOT/.config-backup/shutdown-order.txt"
        else
            echo "Порядок остановки не вычислен"
        fi

    } > "$report_file"

    success "Отчет о зависимостях сохранен: $report_file"
}

# Основная функция
main() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                ERNI-KI Dependency Checker                   ║"
    echo "║               Проверка зависимостей сервисов                ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Создание директории для отчетов
    mkdir -p "$PROJECT_ROOT/.config-backup"

    # Переход в рабочую директорию
    cd "$PROJECT_ROOT"

    # Выполнение всех проверок
    check_circular_dependencies
    echo ""

    calculate_startup_order
    echo ""

    calculate_shutdown_order
    echo ""

    build_dependency_graph
    echo ""

    check_all_dependencies
    echo ""

    generate_dependency_report
}

# Обработка аргументов командной строки
case "${1:-}" in
    --service)
        if [[ -n "${2:-}" ]]; then
            log "Проверка зависимостей для сервиса: $2"
            cd "$PROJECT_ROOT"
            check_service_dependencies "$2"
        else
            error "Укажите имя сервиса для проверки"
            exit 1
        fi
        ;;
    --graph)
        log "Построение графа зависимостей"
        mkdir -p "$PROJECT_ROOT/.config-backup"
        build_dependency_graph
        ;;
    --order)
        log "Вычисление порядка запуска/остановки"
        mkdir -p "$PROJECT_ROOT/.config-backup"
        calculate_startup_order
        calculate_shutdown_order
        ;;
    --cycles)
        log "Проверка циклических зависимостей"
        check_circular_dependencies
        ;;
    --report)
        log "Генерация отчета о зависимостях"
        mkdir -p "$PROJECT_ROOT/.config-backup"
        cd "$PROJECT_ROOT"
        calculate_startup_order
        calculate_shutdown_order
        generate_dependency_report
        ;;
    *)
        main
        ;;
esac
