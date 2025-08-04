#!/bin/bash
# Тестирование производительности GPU для ERNI-KI
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

# Проверка доступности GPU
check_gpu_availability() {
    section "Проверка доступности GPU"
    
    if command -v nvidia-smi &> /dev/null; then
        success "nvidia-smi доступен"
        
        # Информация о GPU
        local gpu_info=$(nvidia-smi --query-gpu=name,driver_version,memory.total,compute_cap --format=csv,noheader,nounits)
        local gpu_name=$(echo "$gpu_info" | cut -d, -f1 | tr -d ' ')
        local driver_version=$(echo "$gpu_info" | cut -d, -f2 | tr -d ' ')
        local memory_total=$(echo "$gpu_info" | cut -d, -f3 | tr -d ' ')
        local compute_cap=$(echo "$gpu_info" | cut -d, -f4 | tr -d ' ')
        
        success "GPU: $gpu_name"
        success "Драйвер: $driver_version"
        success "Память: ${memory_total} MB"
        success "Compute Capability: $compute_cap"
        
        # Проверка температуры и энергопотребления
        local temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits)
        local power=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits)
        local power_limit=$(nvidia-smi --query-gpu=power.limit --format=csv,noheader,nounits)
        
        success "Температура: ${temp}°C"
        success "Энергопотребление: ${power}W / ${power_limit}W"
        
    else
        error "nvidia-smi недоступен"
        return 1
    fi
    echo ""
}

# Проверка GPU в Docker
check_gpu_in_docker() {
    section "Проверка GPU в Docker контейнерах"
    
    # Проверка Ollama
    log "Проверка GPU в Ollama..."
    local ollama_logs=$(docker-compose logs ollama 2>/dev/null | grep -i gpu | tail -3)
    if [[ "$ollama_logs" == *"cuda"* ]]; then
        success "Ollama использует CUDA"
        echo "$ollama_logs" | while read line; do
            info "  $line"
        done
    else
        warning "Ollama может не использовать GPU"
    fi
    
    # Проверка процессов GPU
    log "Процессы, использующие GPU:"
    nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader | while read line; do
        if [[ "$line" == *"ollama"* ]]; then
            success "  $line"
        else
            info "  $line"
        fi
    done
    
    echo ""
}

# Тестирование производительности генерации
test_generation_performance() {
    section "Тестирование производительности генерации текста"
    
    # Проверка доступности Ollama API
    if ! curl -sf http://localhost:11434/api/version &> /dev/null; then
        error "Ollama API недоступен"
        return 1
    fi
    
    success "Ollama API доступен"
    
    # Получение списка моделей
    local models=$(curl -s http://localhost:11434/api/tags | jq -r '.models[].name' 2>/dev/null || echo "")
    if [ -z "$models" ]; then
        warning "Модели не найдены"
        return 1
    fi
    
    local test_model=$(echo "$models" | head -1)
    success "Тестирование с моделью: $test_model"
    
    # Тест 1: Короткий промпт
    log "Тест 1: Короткий промпт"
    local short_prompt="Привет!"
    local start_time=$(date +%s.%N)
    
    local response1=$(curl -s -X POST http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$test_model\",\"prompt\":\"$short_prompt\",\"stream\":false}")
    
    local end_time=$(date +%s.%N)
    local time1=$(echo "scale=3; $end_time - $start_time" | bc)
    
    if [[ "$response1" == *"response"* ]]; then
        success "Время генерации (короткий): ${time1}s"
        local tokens1=$(echo "$response1" | jq -r '.eval_count // 0')
        if [ "$tokens1" -gt 0 ]; then
            local tokens_per_sec1=$(echo "scale=1; $tokens1 / $time1" | bc)
            success "Скорость: ${tokens_per_sec1} токенов/сек"
        fi
    else
        error "Ошибка генерации короткого текста"
    fi
    
    # Тест 2: Длинный промпт
    log "Тест 2: Длинный промпт"
    local long_prompt="Расскажи подробно о преимуществах использования GPU для машинного обучения и генерации текста. Объясни технические детали."
    local start_time2=$(date +%s.%N)
    
    local response2=$(curl -s -X POST http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$test_model\",\"prompt\":\"$long_prompt\",\"stream\":false}")
    
    local end_time2=$(date +%s.%N)
    local time2=$(echo "scale=3; $end_time2 - $start_time2" | bc)
    
    if [[ "$response2" == *"response"* ]]; then
        success "Время генерации (длинный): ${time2}s"
        local tokens2=$(echo "$response2" | jq -r '.eval_count // 0')
        if [ "$tokens2" -gt 0 ]; then
            local tokens_per_sec2=$(echo "scale=1; $tokens2 / $time2" | bc)
            success "Скорость: ${tokens_per_sec2} токенов/сек"
        fi
    else
        error "Ошибка генерации длинного текста"
    fi
    
    # Тест 3: Параллельные запросы
    log "Тест 3: Параллельные запросы (3 одновременно)"
    local parallel_start=$(date +%s.%N)
    
    for i in {1..3}; do
        {
            local req_start=$(date +%s.%N)
            local req_response=$(curl -s -X POST http://localhost:11434/api/generate \
                -H "Content-Type: application/json" \
                -d "{\"model\":\"$test_model\",\"prompt\":\"Тест $i: Напиши короткий ответ\",\"stream\":false}")
            local req_end=$(date +%s.%N)
            local req_time=$(echo "scale=3; $req_end - $req_start" | bc)
            
            if [[ "$req_response" == *"response"* ]]; then
                echo "Запрос $i: ${req_time}s" >> /tmp/gpu_parallel_test.log
            fi
        } &
    done
    
    wait
    local parallel_end=$(date +%s.%N)
    local parallel_total=$(echo "scale=3; $parallel_end - $parallel_start" | bc)
    
    if [ -f /tmp/gpu_parallel_test.log ]; then
        local completed=$(wc -l < /tmp/gpu_parallel_test.log)
        local avg_parallel=$(awk '{sum+=$2; count++} END {print sum/count}' /tmp/gpu_parallel_test.log)
        success "Завершено запросов: $completed/3"
        success "Общее время: ${parallel_total}s"
        success "Среднее время на запрос: ${avg_parallel}s"
        rm -f /tmp/gpu_parallel_test.log
    fi
    
    echo ""
}

# Мониторинг GPU во время работы
monitor_gpu_usage() {
    section "Мониторинг использования GPU"
    
    # Запуск фонового мониторинга
    log "Запуск мониторинга GPU на 30 секунд..."
    
    # Создание файла для логов
    local monitor_log="/tmp/gpu_monitor.log"
    > "$monitor_log"
    
    # Фоновый мониторинг
    {
        for i in {1..30}; do
            local timestamp=$(date +%s)
            local gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits)
            local mem_used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
            local mem_total=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits)
            local temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits)
            local power=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits)
            
            echo "$timestamp,$gpu_util,$mem_used,$mem_total,$temp,$power" >> "$monitor_log"
            sleep 1
        done
    } &
    
    local monitor_pid=$!
    
    # Выполнение тестовой нагрузки
    log "Выполнение тестовой нагрузки..."
    for i in {1..5}; do
        curl -s -X POST http://localhost:11434/api/generate \
            -H "Content-Type: application/json" \
            -d '{"model":"llama3.2:3b","prompt":"Тест нагрузки GPU","stream":false}' > /dev/null &
    done
    
    wait
    kill $monitor_pid 2>/dev/null || true
    
    # Анализ результатов мониторинга
    if [ -f "$monitor_log" ]; then
        log "Анализ результатов мониторинга:"
        
        local max_util=$(awk -F, '{if($2>max) max=$2} END {print max}' "$monitor_log")
        local avg_util=$(awk -F, '{sum+=$2; count++} END {print sum/count}' "$monitor_log")
        local max_mem=$(awk -F, '{if($3>max) max=$3} END {print max}' "$monitor_log")
        local max_temp=$(awk -F, '{if($5>max) max=$5} END {print max}' "$monitor_log")
        local max_power=$(awk -F, '{if($6>max) max=$6} END {print max}' "$monitor_log")
        
        success "Максимальная загрузка GPU: ${max_util}%"
        success "Средняя загрузка GPU: ${avg_util}%"
        success "Максимальное использование памяти: ${max_mem} MB"
        success "Максимальная температура: ${max_temp}°C"
        success "Максимальное энергопотребление: ${max_power}W"
        
        rm -f "$monitor_log"
    fi
    
    echo ""
}

# Сравнение с CPU производительностью
compare_cpu_gpu_performance() {
    section "Сравнение производительности CPU vs GPU"
    
    info "Исторические данные CPU (из предыдущих тестов):"
    info "  Время генерации на CPU: ~2.5s"
    info "  Режим работы: CPU-only"
    
    log "Текущая производительность GPU:"
    local gpu_start=$(date +%s.%N)
    local gpu_response=$(curl -s -X POST http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d '{"model":"llama3.2:3b","prompt":"Сравнительный тест производительности","stream":false}')
    local gpu_end=$(date +%s.%N)
    local gpu_time=$(echo "scale=3; $gpu_end - $gpu_start" | bc)
    
    if [[ "$gpu_response" == *"response"* ]]; then
        success "Время генерации на GPU: ${gpu_time}s"
        
        # Расчет ускорения
        local speedup=$(echo "scale=2; 2.5 / $gpu_time" | bc)
        if (( $(echo "$speedup > 1" | bc -l) )); then
            success "Ускорение: ${speedup}x быстрее CPU"
        elif (( $(echo "$speedup < 1" | bc -l) )); then
            warning "GPU медленнее CPU в ${speedup}x раз"
        else
            info "Производительность GPU и CPU сопоставима"
        fi
        
        # Анализ токенов
        local tokens=$(echo "$gpu_response" | jq -r '.eval_count // 0')
        if [ "$tokens" -gt 0 ]; then
            local tokens_per_sec=$(echo "scale=1; $tokens / $gpu_time" | bc)
            success "Скорость генерации: ${tokens_per_sec} токенов/сек"
        fi
    else
        error "Ошибка тестирования GPU"
    fi
    
    echo ""
}

# Генерация отчета GPU
generate_gpu_report() {
    section "Отчет производительности GPU"
    
    local score=0
    local max_score=5
    local issues=()
    local recommendations=()
    
    # Проверка доступности GPU
    if nvidia-smi &> /dev/null; then
        score=$((score + 1))
        success "GPU: Доступен и работает"
    else
        issues+=("GPU недоступен")
    fi
    
    # Проверка использования GPU в Ollama
    local ollama_gpu=$(docker-compose logs ollama 2>/dev/null | grep -i cuda | wc -l)
    if [ "$ollama_gpu" -gt 0 ]; then
        score=$((score + 1))
        success "Ollama: Использует GPU"
    else
        issues+=("Ollama не использует GPU")
    fi
    
    # Проверка памяти GPU
    local gpu_memory=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
    if [ "$gpu_memory" -gt 1000 ]; then
        score=$((score + 1))
        success "Память GPU: Активно используется (${gpu_memory} MB)"
    else
        warning "Память GPU: Низкое использование (${gpu_memory} MB)"
        recommendations+=("Проверьте настройки GPU в Ollama")
    fi
    
    # Проверка температуры
    local gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits)
    if [ "$gpu_temp" -lt 80 ]; then
        score=$((score + 1))
        success "Температура GPU: Нормальная (${gpu_temp}°C)"
    else
        warning "Температура GPU: Высокая (${gpu_temp}°C)"
        recommendations+=("Проверьте охлаждение GPU")
    fi
    
    # Проверка производительности
    local perf_test=$(curl -s -X POST http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d '{"model":"llama3.2:3b","prompt":"test","stream":false}' | jq -r '.response' 2>/dev/null)
    
    if [[ "$perf_test" != "null" ]] && [[ -n "$perf_test" ]]; then
        score=$((score + 1))
        success "Производительность: GPU генерирует текст"
    else
        issues+=("Проблемы с генерацией на GPU")
    fi
    
    # Итоговая оценка
    local percentage=$((score * 100 / max_score))
    echo ""
    
    if [ "$percentage" -ge 90 ]; then
        success "ИТОГОВАЯ ОЦЕНКА GPU: ${percentage}% - Отлично"
    elif [ "$percentage" -ge 70 ]; then
        info "ИТОГОВАЯ ОЦЕНКА GPU: ${percentage}% - Хорошо"
    elif [ "$percentage" -ge 50 ]; then
        warning "ИТОГОВАЯ ОЦЕНКА GPU: ${percentage}% - Удовлетворительно"
    else
        error "ИТОГОВАЯ ОЦЕНКА GPU: ${percentage}% - Требует внимания"
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
    
    # Общие рекомендации
    echo ""
    info "Рекомендации по оптимизации GPU:"
    echo "  • Используйте более крупные модели для лучшего использования GPU"
    echo "  • Мониторьте температуру GPU при высоких нагрузках"
    echo "  • Рассмотрите обновление драйверов CUDA для лучшей производительности"
    echo "  • Настройте лимиты памяти GPU в Docker Compose"
}

# Основная функция
main() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    GPU Performance Test                     ║"
    echo "║              Тестирование производительности GPU            ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    check_gpu_availability
    check_gpu_in_docker
    test_generation_performance
    monitor_gpu_usage
    compare_cpu_gpu_performance
    generate_gpu_report
    
    echo ""
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║            Тестирование GPU завершено                       ║"
    echo "║         Результаты сохранены в gpu_performance.txt          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Запуск тестирования
main "$@" | tee gpu_performance.txt
