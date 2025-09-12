#!/bin/bash
# Нагрузочное тестирование ERNI-KI
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

# Проверка зависимостей для тестирования
check_dependencies() {
    section "Проверка зависимостей для нагрузочного тестирования"

    # Проверка curl
    if command -v curl &> /dev/null; then
        success "curl доступен"
    else
        error "curl не установлен (требуется для HTTP тестов)"
        return 1
    fi

    # Проверка apache2-utils (ab)
    if command -v ab &> /dev/null; then
        success "Apache Bench (ab) доступен"
    else
        warning "Apache Bench не установлен, устанавливаю..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y apache2-utils
        else
            error "Не удалось установить Apache Bench"
            return 1
        fi
    fi

    # Проверка jq для обработки JSON
    if command -v jq &> /dev/null; then
        success "jq доступен"
    else
        warning "jq не установлен, устанавливаю..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get install -y jq
        else
            warning "jq не установлен, некоторые тесты могут быть ограничены"
        fi
    fi

    echo ""
}

# Тестирование производительности Ollama
test_ollama_performance() {
    section "Тестирование производительности Ollama"

    # Проверка доступности Ollama
    if ! curl -sf http://localhost:11434/api/version &> /dev/null; then
        error "Ollama API недоступен"
        return 1
    fi

    success "Ollama API доступен"

    # Получение списка моделей
    local models=$(curl -s http://localhost:11434/api/tags | jq -r '.models[].name' 2>/dev/null || echo "")
    if [ -z "$models" ]; then
        warning "Модели не найдены, загружаю тестовую модель..."
        docker-compose exec -T ollama ollama pull llama3.2:3b
        models="llama3.2:3b"
    fi

    local test_model=$(echo "$models" | head -1)
    success "Тестирование с моделью: $test_model"

    # Создание тестового промпта
    local test_prompt="Привет! Как дела? Расскажи кратко о себе."

    # Тест 1: Время отклика на простой запрос
    log "Тест 1: Время отклика на простой запрос"
    local start_time=$(date +%s.%N)

    local response=$(curl -s -X POST http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$test_model\",\"prompt\":\"$test_prompt\",\"stream\":false}")

    local end_time=$(date +%s.%N)
    local response_time=$(echo "$end_time - $start_time" | bc)

    if [ -n "$response" ]; then
        success "Время отклика: ${response_time} секунд"

        # Анализ ответа
        local response_length=$(echo "$response" | jq -r '.response' 2>/dev/null | wc -c)
        success "Длина ответа: $response_length символов"
    else
        error "Не удалось получить ответ от модели"
    fi

    # Тест 2: Нагрузочный тест с множественными запросами
    log "Тест 2: Нагрузочный тест (5 параллельных запросов)"
    local concurrent_requests=5
    local total_time=0
    local successful_requests=0

    for i in $(seq 1 $concurrent_requests); do
        {
            local req_start=$(date +%s.%N)
            local req_response=$(curl -s -X POST http://localhost:11434/api/generate \
                -H "Content-Type: application/json" \
                -d "{\"model\":\"$test_model\",\"prompt\":\"Тест $i: Напиши число $i\",\"stream\":false}")
            local req_end=$(date +%s.%N)
            local req_time=$(echo "$req_end - $req_start" | bc)

            if [ -n "$req_response" ]; then
                echo "Запрос $i: ${req_time}s" >> /tmp/ollama_load_test.log
            fi
        } &
    done

    wait

    if [ -f /tmp/ollama_load_test.log ]; then
        local avg_time=$(awk '{sum+=$2; count++} END {print sum/count}' /tmp/ollama_load_test.log)
        local completed=$(wc -l < /tmp/ollama_load_test.log)
        success "Завершено запросов: $completed/$concurrent_requests"
        success "Среднее время отклика: ${avg_time}s"
        rm -f /tmp/ollama_load_test.log
    fi

    # Тест 3: Мониторинг ресурсов во время работы
    log "Тест 3: Мониторинг использования ресурсов"
    local ollama_container=$(docker-compose ps -q ollama)
    if [ -n "$ollama_container" ]; then
        local stats=$(docker stats --no-stream --format "{{.CPUPerc}}\t{{.MemUsage}}" "$ollama_container")
        local cpu_usage=$(echo "$stats" | cut -f1)
        local mem_usage=$(echo "$stats" | cut -f2)
        success "CPU использование: $cpu_usage"
        success "Память использование: $mem_usage"
    fi

    echo ""
}

# Тестирование производительности PostgreSQL
test_postgresql_performance() {
    section "Тестирование производительности PostgreSQL"

    # Проверка доступности БД
    if ! docker-compose exec -T db pg_isready -U postgres &> /dev/null; then
        error "PostgreSQL недоступен"
        return 1
    fi

    success "PostgreSQL доступен"

    # Тест 1: Простые SELECT запросы
    log "Тест 1: Производительность SELECT запросов"
    local start_time=$(date +%s.%N)

    for i in {1..100}; do
        docker-compose exec -T db psql -U postgres -d openwebui -c "SELECT 1;" &> /dev/null
    done

    local end_time=$(date +%s.%N)
    local total_time=$(echo "$end_time - $start_time" | bc)
    local avg_time=$(echo "scale=4; $total_time / 100" | bc)

    success "100 SELECT запросов выполнено за ${total_time}s"
    success "Среднее время на запрос: ${avg_time}s"

    # Тест 2: Подключения к базе данных
    log "Тест 2: Тест множественных подключений"
    local connection_start=$(date +%s.%N)

    for i in {1..20}; do
        {
            docker-compose exec -T db psql -U postgres -d openwebui -c "SELECT current_timestamp;" &> /dev/null
        } &
    done

    wait
    local connection_end=$(date +%s.%N)
    local connection_time=$(echo "$connection_end - $connection_start" | bc)

    success "20 параллельных подключений выполнено за ${connection_time}s"

    # Тест 3: Информация о производительности БД
    log "Тест 3: Статистика производительности БД"

    # Количество активных подключений
    local active_connections=$(docker-compose exec -T db psql -U postgres -d openwebui -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';" | tr -d ' ')
    success "Активных подключений: $active_connections"

    # Размер базы данных
    local db_size=$(docker-compose exec -T db psql -U postgres -d openwebui -t -c "SELECT pg_size_pretty(pg_database_size('openwebui'));" | tr -d ' ')
    success "Размер БД: $db_size"

    # Статистика таблиц
    local table_count=$(docker-compose exec -T db psql -U postgres -d openwebui -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" | tr -d ' ')
    success "Количество таблиц: $table_count"

    echo ""
}

# Тестирование производительности веб-интерфейса
test_webui_performance() {
    section "Тестирование производительности веб-интерфейса"

    # Тест 1: Главная страница через Nginx
    log "Тест 1: Нагрузочный тест главной страницы"

    if command -v ab &> /dev/null; then
        local ab_result=$(ab -n 100 -c 10 -q http://localhost/ 2>&1)

        local requests_per_sec=$(echo "$ab_result" | grep "Requests per second" | awk '{print $4}')
        local time_per_request=$(echo "$ab_result" | grep "Time per request" | head -1 | awk '{print $4}')
        local failed_requests=$(echo "$ab_result" | grep "Failed requests" | awk '{print $3}')

        success "Запросов в секунду: $requests_per_sec"
        success "Время на запрос: ${time_per_request}ms"
        success "Неудачных запросов: $failed_requests"
    else
        warning "Apache Bench недоступен, пропускаю нагрузочный тест"
    fi

    # Тест 2: API endpoints
    log "Тест 2: Производительность API endpoints"

    local endpoints=(
        "http://localhost:9090/health:Auth API"
        "http://localhost:11434/api/version:Ollama API"
        "http://localhost:5001/health:Docling API"
        "http://localhost:9998/tika:Tika API"
    )

    for endpoint_info in "${endpoints[@]}"; do
        local endpoint=$(echo "$endpoint_info" | cut -d: -f1)
        local name=$(echo "$endpoint_info" | cut -d: -f2)

        local start_time=$(date +%s.%N)
        local response=$(curl -s -w "%{http_code}" "$endpoint")
        local end_time=$(date +%s.%N)
        local response_time=$(echo "scale=3; ($end_time - $start_time) * 1000" | bc)

        if [[ "$response" == *"200" ]]; then
            success "$name: ${response_time}ms"
        else
            warning "$name: недоступен или ошибка"
        fi
    done

    # Тест 3: Статические ресурсы
    log "Тест 3: Загрузка статических ресурсов"

    local static_start=$(date +%s.%N)
    curl -s http://localhost/ > /dev/null
    local static_end=$(date +%s.%N)
    local static_time=$(echo "scale=3; ($static_end - $static_start) * 1000" | bc)

    success "Время загрузки главной страницы: ${static_time}ms"

    echo ""
}

# Тестирование производительности Redis
test_redis_performance() {
    section "Тестирование производительности Redis"

    # Проверка доступности Redis
    if ! docker-compose exec -T redis redis-cli ping &> /dev/null; then
        error "Redis недоступен"
        return 1
    fi

    success "Redis доступен"

    # Тест 1: Операции SET/GET
    log "Тест 1: Производительность SET/GET операций"

    local redis_start=$(date +%s.%N)

    # Выполнение 1000 SET операций
    for i in {1..1000}; do
        docker-compose exec -T redis redis-cli set "test_key_$i" "test_value_$i" &> /dev/null
    done

    local redis_set_end=$(date +%s.%N)
    local set_time=$(echo "scale=3; $redis_set_end - $redis_start" | bc)

    # Выполнение 1000 GET операций
    for i in {1..1000}; do
        docker-compose exec -T redis redis-cli get "test_key_$i" &> /dev/null
    done

    local redis_get_end=$(date +%s.%N)
    local get_time=$(echo "scale=3; $redis_get_end - $redis_set_end" | bc)

    success "1000 SET операций: ${set_time}s"
    success "1000 GET операций: ${get_time}s"

    # Очистка тестовых данных
    docker-compose exec -T redis redis-cli flushdb &> /dev/null

    # Тест 2: Информация о производительности Redis
    log "Тест 2: Статистика Redis"

    local redis_info=$(docker-compose exec -T redis redis-cli info stats)
    local total_commands=$(echo "$redis_info" | grep "total_commands_processed" | cut -d: -f2 | tr -d '\r')
    local keyspace_hits=$(echo "$redis_info" | grep "keyspace_hits" | cut -d: -f2 | tr -d '\r')
    local keyspace_misses=$(echo "$redis_info" | grep "keyspace_misses" | cut -d: -f2 | tr -d '\r')

    success "Всего команд обработано: $total_commands"
    success "Попаданий в кэш: $keyspace_hits"
    success "Промахов кэша: $keyspace_misses"

    # Использование памяти Redis
    local memory_info=$(docker-compose exec -T redis redis-cli info memory)
    local used_memory=$(echo "$memory_info" | grep "used_memory_human" | cut -d: -f2 | tr -d '\r')
    local max_memory=$(echo "$memory_info" | grep "maxmemory_human" | cut -d: -f2 | tr -d '\r')

    success "Используется памяти: $used_memory"
    if [ -n "$max_memory" ] && [ "$max_memory" != "0B" ]; then
        success "Максимум памяти: $max_memory"
    else
        info "Лимит памяти не установлен"
    fi

    echo ""
}

# Мониторинг системных ресурсов во время тестов
monitor_system_resources() {
    section "Мониторинг системных ресурсов"

    # CPU загрузка
    local cpu_load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    success "Загрузка CPU: $cpu_load"

    # Использование памяти
    local memory_info=$(free -h | grep "Mem:")
    local total_mem=$(echo "$memory_info" | awk '{print $2}')
    local used_mem=$(echo "$memory_info" | awk '{print $3}')
    local available_mem=$(echo "$memory_info" | awk '{print $7}')

    success "Память: $used_mem/$total_mem используется, $available_mem доступно"

    # Использование диска
    local disk_usage=$(df -h / | tail -1 | awk '{print $5}')
    local disk_available=$(df -h / | tail -1 | awk '{print $4}')

    success "Диск: $disk_usage использовано, $disk_available доступно"

    # Docker статистика
    log "Статистика контейнеров Docker:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" | head -6

    echo ""
}

# Генерация отчета производительности
generate_performance_report() {
    section "Отчет производительности"

    local overall_score=0
    local max_score=5
    local performance_issues=()
    local recommendations=()

    # Оценка Ollama (если тестировался)
    if curl -sf http://localhost:11434/api/version &> /dev/null; then
        overall_score=$((overall_score + 1))
        success "Ollama: Работает и отвечает на запросы"
    else
        performance_issues+=("Ollama недоступен или медленно отвечает")
    fi

    # Оценка PostgreSQL
    if docker-compose exec -T db pg_isready -U postgres &> /dev/null; then
        overall_score=$((overall_score + 1))
        success "PostgreSQL: Работает стабильно"
    else
        performance_issues+=("PostgreSQL недоступен")
    fi

    # Оценка Redis
    if docker-compose exec -T redis redis-cli ping &> /dev/null; then
        overall_score=$((overall_score + 1))
        success "Redis: Работает стабильно"
    else
        performance_issues+=("Redis недоступен")
    fi

    # Оценка веб-интерфейса
    if curl -sf http://localhost &> /dev/null; then
        overall_score=$((overall_score + 1))
        success "Веб-интерфейс: Доступен и отзывчив"
    else
        performance_issues+=("Веб-интерфейс недоступен")
    fi

    # Оценка системных ресурсов
    local cpu_load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_load_num=$(echo "$cpu_load" | cut -d. -f1)

    if [ "$cpu_load_num" -lt 2 ]; then
        overall_score=$((overall_score + 1))
        success "Системные ресурсы: Низкая нагрузка"
    elif [ "$cpu_load_num" -lt 4 ]; then
        success "Системные ресурсы: Умеренная нагрузка"
        recommendations+=("Мониторьте нагрузку CPU при высокой активности")
    else
        warning "Системные ресурсы: Высокая нагрузка"
        recommendations+=("Рассмотрите возможность увеличения ресурсов сервера")
    fi

    # Итоговая оценка
    local percentage=$((overall_score * 100 / max_score))
    echo ""

    if [ "$percentage" -ge 90 ]; then
        success "ИТОГОВАЯ ОЦЕНКА ПРОИЗВОДИТЕЛЬНОСТИ: ${percentage}% - Отлично"
    elif [ "$percentage" -ge 70 ]; then
        info "ИТОГОВАЯ ОЦЕНКА ПРОИЗВОДИТЕЛЬНОСТИ: ${percentage}% - Хорошо"
    elif [ "$percentage" -ge 50 ]; then
        warning "ИТОГОВАЯ ОЦЕНКА ПРОИЗВОДИТЕЛЬНОСТИ: ${percentage}% - Удовлетворительно"
    else
        error "ИТОГОВАЯ ОЦЕНКА ПРОИЗВОДИТЕЛЬНОСТИ: ${percentage}% - Требует внимания"
    fi

    # Проблемы производительности
    if [ ${#performance_issues[@]} -gt 0 ]; then
        echo ""
        error "Обнаруженные проблемы производительности:"
        for issue in "${performance_issues[@]}"; do
            echo "  • $issue"
        done
    fi

    # Рекомендации
    if [ ${#recommendations[@]} -gt 0 ]; then
        echo ""
        warning "Рекомендации по оптимизации:"
        for rec in "${recommendations[@]}"; do
            echo "  • $rec"
        done
    fi
}

# Основная функция
main() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    Load Testing Suite                       ║"
    echo "║              Нагрузочное тестирование ERNI-KI               ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_dependencies
    test_ollama_performance
    test_postgresql_performance
    test_redis_performance
    test_webui_performance
    monitor_system_resources
    generate_performance_report

    echo ""
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║               Нагрузочное тестирование завершено            ║"
    echo "║          Результаты сохранены в load_test_report.txt        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Запуск тестирования
main "$@" | tee load_test_report.txt
