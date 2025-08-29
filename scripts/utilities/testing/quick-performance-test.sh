#!/bin/bash
# Быстрое тестирование производительности ERNI-KI
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

# Быстрый тест API endpoints
quick_api_test() {
    section "Быстрое тестирование API производительности"
    
    local endpoints=(
        "http://localhost:80:Nginx"
        "http://localhost:9090/health:Auth"
        "http://localhost:11434/api/version:Ollama"
        "http://localhost:5001/health:Docling"
        "http://localhost:9998/tika:Tika"
    )
    
    for endpoint_info in "${endpoints[@]}"; do
        local endpoint=$(echo "$endpoint_info" | cut -d: -f1-2)
        local name=$(echo "$endpoint_info" | cut -d: -f3)
        
        log "Тестирование $name..."
        
        local start_time=$(date +%s.%N)
        local response=$(timeout 5 curl -s -w "%{http_code}" "$endpoint" 2>/dev/null || echo "timeout")
        local end_time=$(date +%s.%N)
        
        if [[ "$response" == *"200"* ]]; then
            local response_time=$(echo "scale=0; ($end_time - $start_time) * 1000" | bc 2>/dev/null || echo "N/A")
            success "$name: ${response_time}ms"
        elif [[ "$response" == "timeout" ]]; then
            warning "$name: таймаут (>5s)"
        else
            warning "$name: недоступен"
        fi
    done
    echo ""
}

# Тест базы данных
quick_db_test() {
    section "Быстрое тестирование PostgreSQL"
    
    if docker-compose exec -T db pg_isready -U postgres &> /dev/null; then
        success "PostgreSQL: доступен"
        
        # Простой тест производительности
        local start_time=$(date +%s.%N)
        docker-compose exec -T db psql -U postgres -d openwebui -c "SELECT count(*) FROM information_schema.tables;" &> /dev/null
        local end_time=$(date +%s.%N)
        local query_time=$(echo "scale=0; ($end_time - $start_time) * 1000" | bc 2>/dev/null || echo "N/A")
        
        success "Время запроса к БД: ${query_time}ms"
        
        # Размер БД
        local db_size=$(docker-compose exec -T db psql -U postgres -d openwebui -t -c "SELECT pg_size_pretty(pg_database_size('openwebui'));" 2>/dev/null | tr -d ' ' || echo "N/A")
        success "Размер БД: $db_size"
    else
        error "PostgreSQL недоступен"
    fi
    echo ""
}

# Тест Redis
quick_redis_test() {
    section "Быстрое тестирование Redis"
    
    if docker-compose exec -T redis redis-cli ping 2>/dev/null | grep -q "PONG"; then
        success "Redis: доступен"
        
        # Тест производительности
        local start_time=$(date +%s.%N)
        docker-compose exec -T redis redis-cli set test_key test_value &> /dev/null
        docker-compose exec -T redis redis-cli get test_key &> /dev/null
        docker-compose exec -T redis redis-cli del test_key &> /dev/null
        local end_time=$(date +%s.%N)
        local redis_time=$(echo "scale=0; ($end_time - $start_time) * 1000" | bc 2>/dev/null || echo "N/A")
        
        success "Время SET/GET/DEL: ${redis_time}ms"
        
        # Использование памяти
        local memory_usage=$(docker-compose exec -T redis redis-cli info memory 2>/dev/null | grep "used_memory_human" | cut -d: -f2 | tr -d '\r' || echo "N/A")
        success "Использование памяти: $memory_usage"
    else
        error "Redis недоступен"
    fi
    echo ""
}

# Тест Ollama (упрощенный)
quick_ollama_test() {
    section "Быстрое тестирование Ollama"
    
    if curl -sf http://localhost:11434/api/version &> /dev/null; then
        success "Ollama API: доступен"
        
        # Проверка моделей
        local models=$(docker-compose exec -T ollama ollama list 2>/dev/null | tail -n +2 | wc -l || echo "0")
        success "Загружено моделей: $models"
        
        if [ "$models" -gt 0 ]; then
            # Простой тест генерации (с таймаутом)
            log "Тестирование генерации текста (таймаут 30s)..."
            local start_time=$(date +%s.%N)
            
            local response=$(timeout 30 curl -s -X POST http://localhost:11434/api/generate \
                -H "Content-Type: application/json" \
                -d '{"model":"llama3.2:3b","prompt":"Hi","stream":false}' 2>/dev/null || echo "timeout")
            
            local end_time=$(date +%s.%N)
            
            if [[ "$response" != "timeout" ]] && [[ "$response" == *"response"* ]]; then
                local generation_time=$(echo "scale=1; $end_time - $start_time" | bc 2>/dev/null || echo "N/A")
                success "Время генерации: ${generation_time}s"
            else
                warning "Генерация текста: таймаут или ошибка"
            fi
        else
            warning "Модели не загружены"
        fi
    else
        error "Ollama API недоступен"
    fi
    echo ""
}

# Мониторинг ресурсов
quick_resource_check() {
    section "Мониторинг системных ресурсов"
    
    # CPU
    local cpu_load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    success "Загрузка CPU: $cpu_load"
    
    # Память
    local memory_info=$(free -h | grep "Mem:")
    local used_mem=$(echo "$memory_info" | awk '{print $3}')
    local total_mem=$(echo "$memory_info" | awk '{print $2}')
    local mem_percent=$(free | grep "Mem:" | awk '{printf "%.0f", $3/$2 * 100.0}')
    success "Память: $used_mem/$total_mem (${mem_percent}%)"
    
    # Диск
    local disk_info=$(df -h / | tail -1)
    local disk_used=$(echo "$disk_info" | awk '{print $5}')
    local disk_avail=$(echo "$disk_info" | awk '{print $4}')
    success "Диск: $disk_used использовано, $disk_avail доступно"
    
    # Docker контейнеры
    local running_containers=$(docker ps -q | wc -l)
    success "Запущенных контейнеров: $running_containers"
    
    # Топ 5 контейнеров по использованию CPU
    log "Топ контейнеров по CPU:"
    docker stats --no-stream --format "{{.Container}}: {{.CPUPerc}}" | head -5 | while read line; do
        echo "  $line"
    done
    
    echo ""
}

# Генерация итогового отчета
generate_quick_report() {
    section "Итоговый отчет производительности"
    
    local score=0
    local max_score=6
    local issues=()
    local recommendations=()
    
    # Проверка основных сервисов
    if curl -sf http://localhost &> /dev/null; then
        score=$((score + 1))
        success "Веб-интерфейс: Работает"
    else
        issues+=("Веб-интерфейс недоступен")
    fi
    
    if curl -sf http://localhost:9090/health &> /dev/null; then
        score=$((score + 1))
        success "Auth API: Работает"
    else
        issues+=("Auth API недоступен")
    fi
    
    if curl -sf http://localhost:11434/api/version &> /dev/null; then
        score=$((score + 1))
        success "Ollama API: Работает"
    else
        issues+=("Ollama API недоступен")
    fi
    
    if docker-compose exec -T db pg_isready -U postgres &> /dev/null; then
        score=$((score + 1))
        success "PostgreSQL: Работает"
    else
        issues+=("PostgreSQL недоступен")
    fi
    
    if docker-compose exec -T redis redis-cli ping &> /dev/null; then
        score=$((score + 1))
        success "Redis: Работает"
    else
        issues+=("Redis недоступен")
    fi
    
    # Проверка нагрузки системы
    local cpu_load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_load_num=$(echo "$cpu_load" | cut -d. -f1)
    
    if [ "$cpu_load_num" -lt 4 ]; then
        score=$((score + 1))
        success "Нагрузка системы: Нормальная"
    else
        warning "Нагрузка системы: Высокая ($cpu_load)"
        recommendations+=("Мониторьте нагрузку CPU")
    fi
    
    # Итоговая оценка
    local percentage=$((score * 100 / max_score))
    echo ""
    
    if [ "$percentage" -ge 90 ]; then
        success "ИТОГОВАЯ ОЦЕНКА: ${percentage}% - Отличная производительность"
    elif [ "$percentage" -ge 75 ]; then
        info "ИТОГОВАЯ ОЦЕНКА: ${percentage}% - Хорошая производительность"
    elif [ "$percentage" -ge 50 ]; then
        warning "ИТОГОВАЯ ОЦЕНКА: ${percentage}% - Удовлетворительная производительность"
    else
        error "ИТОГОВАЯ ОЦЕНКА: ${percentage}% - Проблемы с производительностью"
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
    info "Общие рекомендации по оптимизации:"
    echo "  • Регулярно мониторьте использование ресурсов"
    echo "  • Настройте GPU поддержку для Ollama (если доступно)"
    echo "  • Рассмотрите настройку лимитов ресурсов для контейнеров"
    echo "  • Создавайте регулярные бэкапы базы данных"
}

# Основная функция
main() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                Quick Performance Test                        ║"
    echo "║            Быстрое тестирование производительности           ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    quick_api_test
    quick_db_test
    quick_redis_test
    quick_ollama_test
    quick_resource_check
    generate_quick_report
    
    echo ""
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              Быстрое тестирование завершено                 ║"
    echo "║        Результаты сохранены в quick_performance.txt         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Запуск тестирования
main "$@" | tee quick_performance.txt
