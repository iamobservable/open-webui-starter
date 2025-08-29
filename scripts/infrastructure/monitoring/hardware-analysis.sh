#!/bin/bash
# Комплексный анализ железа сервера для ERNI-KI
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

# Функция для форматирования размеров
format_size() {
    local size=$1
    if [ "$size" -gt 1073741824 ]; then
        echo "$(( size / 1073741824 )) GB"
    elif [ "$size" -gt 1048576 ]; then
        echo "$(( size / 1048576 )) MB"
    elif [ "$size" -gt 1024 ]; then
        echo "$(( size / 1024 )) KB"
    else
        echo "${size} B"
    fi
}

# Анализ CPU
analyze_cpu() {
    section "Анализ процессора (CPU)"
    
    # Основная информация о CPU
    if [ -f /proc/cpuinfo ]; then
        local cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
        local cpu_cores=$(nproc)
        local cpu_threads=$(grep -c "processor" /proc/cpuinfo)
        local cpu_arch=$(uname -m)
        
        success "Модель: $cpu_model"
        success "Архитектура: $cpu_arch"
        success "Физические ядра: $cpu_cores"
        success "Логические потоки: $cpu_threads"
        
        # Частота процессора
        if [ -f /proc/cpuinfo ]; then
            local cpu_freq=$(grep "cpu MHz" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
            if [ -n "$cpu_freq" ]; then
                success "Текущая частота: ${cpu_freq} MHz"
            fi
        fi
        
        # Максимальная частота
        if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
            local max_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null)
            if [ -n "$max_freq" ]; then
                success "Максимальная частота: $((max_freq / 1000)) MHz"
            fi
        fi
        
        # Кэш процессора
        local l3_cache=$(grep "cache size" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
        if [ -n "$l3_cache" ]; then
            success "Кэш L3: $l3_cache"
        fi
        
        # Флаги процессора (важные для виртуализации и производительности)
        local cpu_flags=$(grep "flags" /proc/cpuinfo | head -1 | cut -d: -f2)
        if echo "$cpu_flags" | grep -q "avx2"; then
            success "AVX2 поддерживается (ускорение вычислений)"
        else
            warning "AVX2 не поддерживается"
        fi
        
        if echo "$cpu_flags" | grep -q "sse4_2"; then
            success "SSE4.2 поддерживается"
        else
            warning "SSE4.2 не поддерживается"
        fi
        
        # Текущая загрузка CPU
        local cpu_load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
        success "Текущая загрузка: $cpu_load"
        
        # Оценка производительности для ERNI-KI
        if [ "$cpu_cores" -ge 8 ]; then
            success "CPU отлично подходит для ERNI-KI (8+ ядер)"
        elif [ "$cpu_cores" -ge 4 ]; then
            info "CPU подходит для ERNI-KI (4+ ядра)"
        else
            warning "CPU может быть недостаточно мощным (менее 4 ядер)"
        fi
    else
        error "Не удалось получить информацию о CPU"
    fi
    echo ""
}

# Анализ памяти
analyze_memory() {
    section "Анализ оперативной памяти (RAM)"
    
    if [ -f /proc/meminfo ]; then
        local total_mem=$(grep "MemTotal" /proc/meminfo | awk '{print $2}')
        local available_mem=$(grep "MemAvailable" /proc/meminfo | awk '{print $2}')
        local free_mem=$(grep "MemFree" /proc/meminfo | awk '{print $2}')
        local cached_mem=$(grep "Cached" /proc/meminfo | head -1 | awk '{print $2}')
        local buffers_mem=$(grep "Buffers" /proc/meminfo | awk '{print $2}')
        
        # Конвертация в человекочитаемый формат
        local total_gb=$((total_mem / 1024 / 1024))
        local available_gb=$((available_mem / 1024 / 1024))
        local used_mem=$((total_mem - available_mem))
        local used_gb=$((used_mem / 1024 / 1024))
        local usage_percent=$((used_mem * 100 / total_mem))
        
        success "Общий объем: ${total_gb} GB"
        success "Используется: ${used_gb} GB (${usage_percent}%)"
        success "Доступно: ${available_gb} GB"
        success "Кэш: $((cached_mem / 1024)) MB"
        success "Буферы: $((buffers_mem / 1024)) MB"
        
        # Информация о swap
        local swap_total=$(grep "SwapTotal" /proc/meminfo | awk '{print $2}')
        local swap_free=$(grep "SwapFree" /proc/meminfo | awk '{print $2}')
        local swap_used=$((swap_total - swap_free))
        
        if [ "$swap_total" -gt 0 ]; then
            success "Swap общий: $((swap_total / 1024 / 1024)) GB"
            success "Swap используется: $((swap_used / 1024)) MB"
        else
            warning "Swap не настроен"
        fi
        
        # Оценка для ERNI-KI
        if [ "$total_gb" -ge 32 ]; then
            success "RAM отлично подходит для ERNI-KI (32+ GB)"
        elif [ "$total_gb" -ge 16 ]; then
            info "RAM подходит для ERNI-KI (16+ GB)"
        elif [ "$total_gb" -ge 8 ]; then
            warning "RAM минимально подходит для ERNI-KI (8+ GB)"
        else
            error "RAM недостаточно для ERNI-KI (менее 8 GB)"
        fi
        
        if [ "$usage_percent" -gt 80 ]; then
            warning "Высокое использование памяти (${usage_percent}%)"
        elif [ "$usage_percent" -gt 60 ]; then
            info "Умеренное использование памяти (${usage_percent}%)"
        else
            success "Низкое использование памяти (${usage_percent}%)"
        fi
    else
        error "Не удалось получить информацию о памяти"
    fi
    echo ""
}

# Анализ дискового пространства
analyze_storage() {
    section "Анализ дискового пространства"
    
    # Основная информация о дисках
    success "Использование дискового пространства:"
    df -h | grep -E "^/dev/" | while read line; do
        echo "  $line"
    done
    
    # Детальная информация о корневом разделе
    local root_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    local root_available=$(df -h / | tail -1 | awk '{print $4}')
    
    success "Корневой раздел: ${root_usage}% использовано, ${root_available} доступно"
    
    # Проверка места для Docker
    local docker_dir="/var/lib/docker"
    if [ -d "$docker_dir" ]; then
        local docker_size=$(du -sh "$docker_dir" 2>/dev/null | cut -f1)
        success "Размер Docker данных: $docker_size"
    fi
    
    # Проверка места для проекта
    local project_size=$(du -sh . 2>/dev/null | cut -f1)
    success "Размер проекта ERNI-KI: $project_size"
    
    # Тест скорости записи/чтения
    log "Тестирование скорости диска..."
    local write_speed=$(dd if=/dev/zero of=/tmp/test_write bs=1M count=100 2>&1 | grep -o '[0-9.]* MB/s' | tail -1)
    local read_speed=$(dd if=/tmp/test_write of=/dev/null bs=1M 2>&1 | grep -o '[0-9.]* MB/s' | tail -1)
    rm -f /tmp/test_write
    
    if [ -n "$write_speed" ]; then
        success "Скорость записи: $write_speed"
    fi
    if [ -n "$read_speed" ]; then
        success "Скорость чтения: $read_speed"
    fi
    
    # Оценка для ERNI-KI
    if [ "$root_usage" -lt 50 ]; then
        success "Достаточно места для ERNI-KI"
    elif [ "$root_usage" -lt 80 ]; then
        warning "Место ограничено, рекомендуется очистка"
    else
        error "Критически мало места (${root_usage}%)"
    fi
    echo ""
}

# Анализ GPU
analyze_gpu() {
    section "Анализ графического процессора (GPU)"
    
    # Проверка NVIDIA GPU
    if command -v nvidia-smi &> /dev/null; then
        success "NVIDIA GPU обнаружен:"
        nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,temperature.gpu,power.draw --format=csv,noheader,nounits | while read line; do
            echo "  $line"
        done
        
        # Проверка CUDA
        if command -v nvcc &> /dev/null; then
            local cuda_version=$(nvcc --version | grep "release" | awk '{print $6}' | cut -d, -f1)
            success "CUDA версия: $cuda_version"
        else
            warning "CUDA toolkit не установлен"
        fi
        
        # Проверка Docker GPU поддержки
        if docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi &> /dev/null; then
            success "Docker GPU поддержка работает"
        else
            warning "Docker GPU поддержка не настроена"
        fi
        
        success "GPU отлично подходит для Ollama с ускорением"
    else
        # Проверка AMD GPU
        if command -v rocm-smi &> /dev/null; then
            success "AMD GPU обнаружен:"
            rocm-smi --showproductname --showmeminfo
            info "AMD GPU может работать с Ollama через ROCm"
        else
            # Проверка Intel GPU
            if lspci | grep -i "vga\|3d\|display" | grep -i intel &> /dev/null; then
                local intel_gpu=$(lspci | grep -i "vga\|3d\|display" | grep -i intel | head -1)
                info "Intel GPU обнаружен: $intel_gpu"
                warning "Intel GPU имеет ограниченную поддержку для Ollama"
            else
                warning "Дискретный GPU не обнаружен"
                info "Ollama будет работать на CPU (медленнее)"
            fi
        fi
    fi
    echo ""
}

# Анализ сети
analyze_network() {
    section "Анализ сетевых возможностей"
    
    # Сетевые интерфейсы
    success "Активные сетевые интерфейсы:"
    ip addr show | grep -E "^[0-9]+:" | while read line; do
        local interface=$(echo "$line" | awk '{print $2}' | sed 's/://')
        local status=$(echo "$line" | grep -o "state [A-Z]*" | awk '{print $2}')
        echo "  $interface: $status"
    done
    
    # Тест скорости интернета (если доступен)
    if command -v curl &> /dev/null; then
        log "Тестирование скорости загрузки..."
        local download_speed=$(curl -o /dev/null -s -w '%{speed_download}' http://speedtest.wdc01.softlayer.com/downloads/test10.zip | awk '{print int($1/1024/1024)}')
        if [ "$download_speed" -gt 0 ]; then
            success "Скорость загрузки: ~${download_speed} MB/s"
        fi
    fi
    
    # Проверка портов Docker
    success "Проверка портов ERNI-KI:"
    local ports=(80 5432 6379 8080 9090 11434)
    for port in "${ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep ":$port " &> /dev/null; then
            success "Порт $port: занят (сервис работает)"
        else
            info "Порт $port: свободен"
        fi
    done
    
    # Проверка Docker сети
    if command -v docker &> /dev/null; then
        local docker_networks=$(docker network ls --format "{{.Name}}" | wc -l)
        success "Docker сетей: $docker_networks"
    fi
    echo ""
}

# Анализ операционной системы
analyze_os() {
    section "Анализ операционной системы"
    
    # Основная информация об ОС
    if [ -f /etc/os-release ]; then
        local os_name=$(grep "PRETTY_NAME" /etc/os-release | cut -d= -f2 | tr -d '"')
        local os_version=$(grep "VERSION_ID" /etc/os-release | cut -d= -f2 | tr -d '"')
        success "ОС: $os_name"
        success "Версия: $os_version"
    fi
    
    # Версия ядра
    local kernel_version=$(uname -r)
    success "Ядро: $kernel_version"
    
    # Время работы системы
    local uptime_info=$(uptime -p)
    success "Время работы: $uptime_info"
    
    # Проверка systemd
    if command -v systemctl &> /dev/null; then
        success "Systemd: доступен"
    else
        warning "Systemd: недоступен"
    fi
    
    # Проверка cgroups v2 (важно для Docker)
    if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
        success "Cgroups v2: поддерживается"
    else
        info "Cgroups v1: используется"
    fi
    echo ""
}

# Генерация итогового отчета
generate_summary() {
    section "Итоговая оценка совместимости с ERNI-KI"
    
    local score=0
    local max_score=10
    local recommendations=()
    
    # Оценка CPU
    local cpu_cores=$(nproc)
    if [ "$cpu_cores" -ge 8 ]; then
        score=$((score + 3))
        success "CPU: Отлично (${cpu_cores} ядер)"
    elif [ "$cpu_cores" -ge 4 ]; then
        score=$((score + 2))
        info "CPU: Хорошо (${cpu_cores} ядра)"
    else
        score=$((score + 1))
        warning "CPU: Удовлетворительно (${cpu_cores} ядра)"
        recommendations+=("Рекомендуется CPU с 4+ ядрами для лучшей производительности")
    fi
    
    # Оценка RAM
    local total_mem=$(grep "MemTotal" /proc/meminfo | awk '{print $2}')
    local total_gb=$((total_mem / 1024 / 1024))
    if [ "$total_gb" -ge 32 ]; then
        score=$((score + 3))
        success "RAM: Отлично (${total_gb} GB)"
    elif [ "$total_gb" -ge 16 ]; then
        score=$((score + 2))
        info "RAM: Хорошо (${total_gb} GB)"
    elif [ "$total_gb" -ge 8 ]; then
        score=$((score + 1))
        warning "RAM: Минимально (${total_gb} GB)"
        recommendations+=("Рекомендуется 16+ GB RAM для комфортной работы")
    else
        error "RAM: Недостаточно (${total_gb} GB)"
        recommendations+=("КРИТИЧНО: Требуется минимум 8 GB RAM")
    fi
    
    # Оценка диска
    local root_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$root_usage" -lt 50 ]; then
        score=$((score + 2))
        success "Диск: Достаточно места"
    elif [ "$root_usage" -lt 80 ]; then
        score=$((score + 1))
        warning "Диск: Ограниченное место"
        recommendations+=("Рекомендуется освободить место на диске")
    else
        error "Диск: Критически мало места"
        recommendations+=("КРИТИЧНО: Освободите место на диске")
    fi
    
    # Оценка GPU
    if command -v nvidia-smi &> /dev/null; then
        score=$((score + 2))
        success "GPU: NVIDIA GPU доступен"
    else
        info "GPU: Работа на CPU"
        recommendations+=("Для ускорения Ollama рекомендуется NVIDIA GPU")
    fi
    
    # Итоговая оценка
    local percentage=$((score * 100 / max_score))
    echo ""
    if [ "$percentage" -ge 80 ]; then
        success "ИТОГОВАЯ ОЦЕНКА: ${percentage}% - Отлично подходит для ERNI-KI"
    elif [ "$percentage" -ge 60 ]; then
        info "ИТОГОВАЯ ОЦЕНКА: ${percentage}% - Хорошо подходит для ERNI-KI"
    elif [ "$percentage" -ge 40 ]; then
        warning "ИТОГОВАЯ ОЦЕНКА: ${percentage}% - Удовлетворительно для ERNI-KI"
    else
        error "ИТОГОВАЯ ОЦЕНКА: ${percentage}% - Не рекомендуется для ERNI-KI"
    fi
    
    # Рекомендации
    if [ ${#recommendations[@]} -gt 0 ]; then
        echo ""
        warning "Рекомендации по улучшению:"
        for rec in "${recommendations[@]}"; do
            echo "  • $rec"
        done
    fi
}

# Основная функция
main() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                 ERNI-KI Hardware Analysis                   ║"
    echo "║              Комплексный анализ железа сервера              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    analyze_os
    analyze_cpu
    analyze_memory
    analyze_storage
    analyze_gpu
    analyze_network
    generate_summary
    
    echo ""
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    Анализ завершен                          ║"
    echo "║         Результаты сохранены в hardware_report.txt          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Запуск анализа
main "$@" | tee hardware_report.txt
