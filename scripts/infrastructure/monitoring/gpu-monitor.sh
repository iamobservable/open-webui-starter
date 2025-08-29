#!/bin/bash
# Мониторинг GPU для ERNI-KI
# Автор: Альтэон Шульц (Tech Lead)

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

# Проверка доступности nvidia-smi
check_nvidia_smi() {
    if ! command -v nvidia-smi &> /dev/null; then
        error "nvidia-smi не найден. Установите драйверы NVIDIA."
        exit 1
    fi
}

# Отображение информации о GPU
show_gpu_info() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    GPU Monitor ERNI-KI                      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Основная информация о GPU
    local gpu_info=$(nvidia-smi --query-gpu=name,driver_version,memory.total,compute_cap --format=csv,noheader,nounits)
    local gpu_name=$(echo "$gpu_info" | cut -d, -f1 | tr -d ' ')
    local driver_version=$(echo "$gpu_info" | cut -d, -f2 | tr -d ' ')
    local memory_total=$(echo "$gpu_info" | cut -d, -f3 | tr -d ' ')
    local compute_cap=$(echo "$gpu_info" | cut -d, -f4 | tr -d ' ')

    success "GPU: $gpu_name"
    success "Драйвер: $driver_version"
    success "Память: ${memory_total} MB"
    success "Compute Capability: $compute_cap"
    echo ""
}

# Мониторинг в реальном времени
monitor_realtime() {
    local interval=${1:-2}

    echo -e "${CYAN}Мониторинг GPU (обновление каждые ${interval}s, Ctrl+C для выхода)${NC}"
    echo ""

    # Заголовок таблицы
    printf "%-8s %-6s %-12s %-8s %-6s %-8s %-10s\n" "TIME" "GPU%" "MEMORY" "TEMP" "FAN" "POWER" "PROCESSES"
    echo "────────────────────────────────────────────────────────────────────────────"

    while true; do
        local timestamp=$(date +%H:%M:%S)

        # Получение метрик GPU
        local gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits)
        local mem_used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
        local mem_total=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits)
        local temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits)
        local fan=$(nvidia-smi --query-gpu=fan.speed --format=csv,noheader,nounits)
        local power=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits)

        # Процессы, использующие GPU
        local processes=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader | wc -l)

        # Форматирование памяти
        local mem_percent=$(echo "scale=0; $mem_used * 100 / $mem_total" | bc 2>/dev/null || echo "0")
        local mem_display="${mem_used}/${mem_total}MB"

        # Цветовое кодирование
        local gpu_color=""
        local temp_color=""
        local power_color=""

        # Цвет для загрузки GPU
        if [ "$gpu_util" -gt 80 ]; then
            gpu_color="${RED}"
        elif [ "$gpu_util" -gt 50 ]; then
            gpu_color="${YELLOW}"
        else
            gpu_color="${GREEN}"
        fi

        # Цвет для температуры
        if [ "$temp" -gt 80 ]; then
            temp_color="${RED}"
        elif [ "$temp" -gt 70 ]; then
            temp_color="${YELLOW}"
        else
            temp_color="${GREEN}"
        fi

        # Цвет для энергопотребления
        local power_int=$(echo "$power" | cut -d. -f1)
        if [ "$power_int" -gt 60 ]; then
            power_color="${RED}"
        elif [ "$power_int" -gt 40 ]; then
            power_color="${YELLOW}"
        else
            power_color="${GREEN}"
        fi

        # Вывод строки мониторинга
        printf "%-8s ${gpu_color}%-6s${NC} %-12s ${temp_color}%-6s°C${NC} %-6s%% ${power_color}%-8sW${NC} %-10s\n" \
            "$timestamp" "${gpu_util}%" "$mem_display" "$temp" "$fan" "$power" "$processes"

        sleep "$interval"
    done
}

# Краткий статус
show_status() {
    local gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits)
    local mem_used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
    local mem_total=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits)
    local temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits)
    local power=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits)

    echo "GPU Status:"
    echo "  Загрузка: ${gpu_util}%"
    echo "  Память: ${mem_used}/${mem_total} MB ($(echo "scale=0; $mem_used * 100 / $mem_total" | bc)%)"
    echo "  Температура: ${temp}°C"
    echo "  Энергопотребление: ${power}W"

    # Процессы
    local processes=$(nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader)
    if [ -n "$processes" ]; then
        echo "  Процессы:"
        echo "$processes" | while read line; do
            echo "    $line"
        done
    else
        echo "  Процессы: Нет активных"
    fi
}

# Проверка здоровья GPU
health_check() {
    local issues=0

    echo "Проверка здоровья GPU:"

    # Проверка температуры
    local temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits)
    if [ "$temp" -gt 85 ]; then
        error "Критическая температура: ${temp}°C"
        issues=$((issues + 1))
    elif [ "$temp" -gt 75 ]; then
        warning "Высокая температура: ${temp}°C"
    else
        success "Температура в норме: ${temp}°C"
    fi

    # Проверка энергопотребления
    local power=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits)
    local power_limit=$(nvidia-smi --query-gpu=power.limit --format=csv,noheader,nounits)
    local power_percent=$(echo "scale=0; $power * 100 / $power_limit" | bc)

    if [ "$power_percent" -gt 95 ]; then
        warning "Высокое энергопотребление: ${power}W (${power_percent}%)"
    else
        success "Энергопотребление в норме: ${power}W (${power_percent}%)"
    fi

    # Проверка памяти
    local mem_used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
    local mem_total=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits)
    local mem_percent=$(echo "scale=0; $mem_used * 100 / $mem_total" | bc)

    if [ "$mem_percent" -gt 90 ]; then
        warning "Высокое использование памяти: ${mem_percent}%"
    else
        success "Использование памяти в норме: ${mem_percent}%"
    fi

    # Проверка ошибок (ECC не поддерживается на Quadro P2200)
    # local ecc_errors=$(nvidia-smi --query-gpu=ecc.errors.corrected.total --format=csv,noheader,nounits 2>/dev/null || echo "N/A")
    # if [[ "$ecc_errors" != "N/A" ]] && [[ "$ecc_errors" =~ ^[0-9]+$ ]] && [ "$ecc_errors" -gt 0 ]; then
    #     warning "Обнаружены ECC ошибки: $ecc_errors"
    # fi

    if [ "$issues" -eq 0 ]; then
        success "GPU работает нормально"
        return 0
    else
        error "Обнаружено $issues проблем с GPU"
        return 1
    fi
}

# Логирование в файл
log_to_file() {
    local logfile=${1:-"gpu_monitor.log"}
    local interval=${2:-60}

    log "Запуск логирования GPU в файл: $logfile (интервал: ${interval}s)"

    # Заголовок лог-файла
    echo "timestamp,gpu_util,mem_used,mem_total,temp,fan,power,processes" > "$logfile"

    while true; do
        local timestamp=$(date +%Y-%m-%d\ %H:%M:%S)
        local gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits)
        local mem_used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
        local mem_total=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits)
        local temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits)
        local fan=$(nvidia-smi --query-gpu=fan.speed --format=csv,noheader,nounits)
        local power=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits)
        local processes=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader | wc -l)

        echo "$timestamp,$gpu_util,$mem_used,$mem_total,$temp,$fan,$power,$processes" >> "$logfile"

        sleep "$interval"
    done
}

# Показать помощь
show_help() {
    echo "GPU Monitor для ERNI-KI"
    echo ""
    echo "Использование: $0 [КОМАНДА] [ОПЦИИ]"
    echo ""
    echo "Команды:"
    echo "  monitor [интервал]    - Мониторинг в реальном времени (по умолчанию: 2s)"
    echo "  status               - Показать текущий статус GPU"
    echo "  health               - Проверка здоровья GPU"
    echo "  log [файл] [интервал] - Логирование в файл (по умолчанию: gpu_monitor.log, 60s)"
    echo "  info                 - Показать информацию о GPU"
    echo "  help                 - Показать эту справку"
    echo ""
    echo "Примеры:"
    echo "  $0 monitor           - Мониторинг каждые 2 секунды"
    echo "  $0 monitor 5         - Мониторинг каждые 5 секунд"
    echo "  $0 status            - Краткий статус"
    echo "  $0 health            - Проверка здоровья"
    echo "  $0 log gpu.log 30    - Логирование каждые 30 секунд"
}

# Основная функция
main() {
    check_nvidia_smi

    case "${1:-monitor}" in
        "monitor")
            show_gpu_info
            monitor_realtime "${2:-2}"
            ;;
        "status")
            show_gpu_info
            show_status
            ;;
        "health")
            show_gpu_info
            health_check
            ;;
        "log")
            show_gpu_info
            log_to_file "${2:-gpu_monitor.log}" "${3:-60}"
            ;;
        "info")
            show_gpu_info
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            error "Неизвестная команда: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Обработка сигналов
trap 'echo -e "\n${CYAN}Мониторинг остановлен${NC}"; exit 0' INT TERM

# Запуск
main "$@"
