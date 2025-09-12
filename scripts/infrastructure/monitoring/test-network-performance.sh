#!/bin/bash

# ERNI-KI Network Performance Testing Script
# Скрипт для тестирования производительности оптимизированной сетевой архитектуры

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции логирования
log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"; }
info() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"; }

# Конфигурация тестов
RESULTS_DIR="test-results/network-performance-$(date +%Y%m%d-%H%M%S)"
CONCURRENT_REQUESTS=10
TEST_DURATION=60
WARMUP_TIME=10

# Создание директории для результатов
setup_test_environment() {
    log "Настройка тестового окружения..."
    mkdir -p "$RESULTS_DIR"

    # Проверка доступности инструментов
    local tools=("curl" "ab" "wrk" "docker" "jq")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            warn "$tool не установлен, некоторые тесты могут быть пропущены"
        fi
    done

    log "Тестовое окружение настроено: $RESULTS_DIR"
}

# Проверка состояния сервисов
check_services_health() {
    log "Проверка состояния сервисов..."

    local services=(
        "erni-ki-nginx-1:80"
        "erni-ki-litellm:4000"
        "erni-ki-openwebui-1:8080"
        "erni-ki-ollama:11434"
        "erni-ki-redis-1:6379"
        "erni-ki-db:5432"
    )

    local healthy=0
    local total=${#services[@]}

    for service in "${services[@]}"; do
        local container=$(echo "$service" | cut -d: -f1)
        local port=$(echo "$service" | cut -d: -f2)

        if docker exec "$container" timeout 5 bash -c "echo > /dev/tcp/localhost/$port" 2>/dev/null; then
            info "✓ $container:$port - Healthy"
            ((healthy++))
        else
            warn "✗ $container:$port - Unhealthy"
        fi
    done

    echo "Services Health: $healthy/$total" > "$RESULTS_DIR/services-health.txt"

    if [[ $healthy -lt $((total * 3 / 4)) ]]; then
        error "Слишком много нездоровых сервисов ($healthy/$total). Остановка тестов."
        exit 1
    fi

    log "Проверка состояния завершена: $healthy/$total сервисов здоровы"
}

# Тест латентности между сервисами
test_internal_latency() {
    log "Тестирование латентности между сервисами..."

    local latency_file="$RESULTS_DIR/internal-latency.txt"
    echo "# Internal Service Latency Test" > "$latency_file"
    echo "# Format: Source -> Target: avg_ms min_ms max_ms" >> "$latency_file"

    # Тестируемые маршруты (статические IP адреса)
    local routes=(
        "erni-ki-nginx-1:172.21.0.30:4000:Nginx->LiteLLM"
        "erni-ki-nginx-1:172.21.0.20:8080:Nginx->OpenWebUI"
        "erni-ki-litellm:172.21.0.90:11434:LiteLLM->Ollama"
        "erni-ki-litellm:172.21.0.40:5432:LiteLLM->PostgreSQL"
        "erni-ki-litellm:172.21.0.50:6379:LiteLLM->Redis"
        "erni-ki-openwebui-1:172.21.0.60:8080:OpenWebUI->SearXNG"
    )

    for route in "${routes[@]}"; do
        IFS=':' read -r container target_ip target_port description <<< "$route"

        info "Тестирование: $description"

        # Ping тест (если доступен)
        if docker exec "$container" which ping >/dev/null 2>&1; then
            local ping_result=$(docker exec "$container" ping -c 10 -W 1 "$target_ip" 2>/dev/null | tail -1 | awk -F'/' '{print $5}' || echo "N/A")
            echo "$description: ping_avg=${ping_result}ms" >> "$latency_file"
        fi

        # TCP connection test
        local tcp_times=()
        for i in {1..10}; do
            local start_time=$(date +%s%N)
            if docker exec "$container" timeout 2 bash -c "echo > /dev/tcp/$target_ip/$target_port" 2>/dev/null; then
                local end_time=$(date +%s%N)
                local duration=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds
                tcp_times+=("$duration")
            fi
        done

        if [[ ${#tcp_times[@]} -gt 0 ]]; then
            local avg=$(( $(IFS=+; echo "$((${tcp_times[*]}))") / ${#tcp_times[@]} ))
            local min=$(printf '%s\n' "${tcp_times[@]}" | sort -n | head -1)
            local max=$(printf '%s\n' "${tcp_times[@]}" | sort -n | tail -1)
            echo "$description: tcp_avg=${avg}ms tcp_min=${min}ms tcp_max=${max}ms" >> "$latency_file"
            info "  TCP: avg=${avg}ms min=${min}ms max=${max}ms"
        else
            warn "  TCP connection failed"
            echo "$description: tcp_connection=FAILED" >> "$latency_file"
        fi
    done

    log "Тест латентности завершен"
}

# Тест пропускной способности HTTP
test_http_throughput() {
    log "Тестирование пропускной способности HTTP..."

    local throughput_file="$RESULTS_DIR/http-throughput.txt"
    echo "# HTTP Throughput Test Results" > "$throughput_file"

    # Тестируемые endpoints
    local endpoints=(
        "http://localhost:80/health:Nginx-Health"
        "http://localhost:4000/health:LiteLLM-Health"
        "http://localhost:8080/health:Cloudflare-Tunnel"
    )

    for endpoint in "${endpoints[@]}"; do
        IFS=':' read -r url description <<< "$endpoint"

        info "Тестирование пропускной способности: $description"

        # Apache Bench test
        if command -v ab &> /dev/null; then
            local ab_result=$(ab -n 1000 -c 10 -q "$url" 2>/dev/null | grep "Requests per second" | awk '{print $4}' || echo "N/A")
            echo "$description: ab_rps=$ab_result" >> "$throughput_file"
            info "  Apache Bench: $ab_result req/sec"
        fi

        # wrk test (если доступен)
        if command -v wrk &> /dev/null; then
            local wrk_result=$(wrk -t4 -c10 -d10s --latency "$url" 2>/dev/null | grep "Requests/sec" | awk '{print $2}' || echo "N/A")
            echo "$description: wrk_rps=$wrk_result" >> "$throughput_file"
            info "  wrk: $wrk_result req/sec"
        fi

        # curl timing test
        local curl_times=()
        for i in {1..10}; do
            local curl_time=$(curl -w "%{time_total}" -s -o /dev/null "$url" 2>/dev/null || echo "999")
            curl_times+=("$curl_time")
        done

        if [[ ${#curl_times[@]} -gt 0 ]]; then
            local avg_time=$(echo "${curl_times[@]}" | tr ' ' '\n' | awk '{sum+=$1} END {print sum/NR}')
            echo "$description: curl_avg_time=${avg_time}s" >> "$throughput_file"
            info "  cURL average time: ${avg_time}s"
        fi
    done

    log "Тест пропускной способности HTTP завершен"
}

# Тест производительности AI сервисов
test_ai_performance() {
    log "Тестирование производительности AI сервисов..."

    local ai_file="$RESULTS_DIR/ai-performance.txt"
    echo "# AI Services Performance Test" > "$ai_file"

    # Тест LiteLLM Gateway
    info "Тестирование LiteLLM Gateway..."
    local litellm_start=$(date +%s%N)
    local litellm_response=$(curl -s -X POST "http://localhost:4000/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "llama3.2",
            "messages": [{"role": "user", "content": "Hello, this is a performance test."}],
            "max_tokens": 50,
            "stream": false
        }' 2>/dev/null || echo '{"error": "failed"}')
    local litellm_end=$(date +%s%N)
    local litellm_duration=$(( (litellm_end - litellm_start) / 1000000 ))

    if echo "$litellm_response" | jq -e '.choices[0].message.content' >/dev/null 2>&1; then
        echo "LiteLLM: response_time=${litellm_duration}ms status=SUCCESS" >> "$ai_file"
        info "  LiteLLM: ${litellm_duration}ms - SUCCESS"
    else
        echo "LiteLLM: response_time=${litellm_duration}ms status=FAILED" >> "$ai_file"
        warn "  LiteLLM: ${litellm_duration}ms - FAILED"
    fi

    # Тест прямого доступа к Ollama
    info "Тестирование прямого доступа к Ollama..."
    local ollama_start=$(date +%s%N)
    local ollama_response=$(curl -s -X POST "http://localhost:11434/api/generate" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "llama3.2",
            "prompt": "Hello, this is a performance test.",
            "stream": false
        }' 2>/dev/null || echo '{"error": "failed"}')
    local ollama_end=$(date +%s%N)
    local ollama_duration=$(( (ollama_end - ollama_start) / 1000000 ))

    if echo "$ollama_response" | jq -e '.response' >/dev/null 2>&1; then
        echo "Ollama: response_time=${ollama_duration}ms status=SUCCESS" >> "$ai_file"
        info "  Ollama: ${ollama_duration}ms - SUCCESS"
    else
        echo "Ollama: response_time=${ollama_duration}ms status=FAILED" >> "$ai_file"
        warn "  Ollama: ${ollama_duration}ms - FAILED"
    fi

    log "Тест производительности AI сервисов завершен"
}

# Тест производительности базы данных
test_database_performance() {
    log "Тестирование производительности базы данных..."

    local db_file="$RESULTS_DIR/database-performance.txt"
    echo "# Database Performance Test" > "$db_file"

    # Тест подключения к PostgreSQL
    info "Тестирование PostgreSQL..."
    local pg_times=()
    for i in {1..10}; do
        local start_time=$(date +%s%N)
        if docker exec erni-ki-db pg_isready -U postgres >/dev/null 2>&1; then
            local end_time=$(date +%s%N)
            local duration=$(( (end_time - start_time) / 1000000 ))
            pg_times+=("$duration")
        fi
    done

    if [[ ${#pg_times[@]} -gt 0 ]]; then
        local avg=$(( $(IFS=+; echo "$((${pg_times[*]}))") / ${#pg_times[@]} ))
        echo "PostgreSQL: connection_avg=${avg}ms status=SUCCESS" >> "$db_file"
        info "  PostgreSQL connection: ${avg}ms average"
    else
        echo "PostgreSQL: connection=FAILED" >> "$db_file"
        warn "  PostgreSQL connection failed"
    fi

    # Тест Redis
    info "Тестирование Redis..."
    local redis_times=()
    for i in {1..10}; do
        local start_time=$(date +%s%N)
        if docker exec erni-ki-redis-1 redis-cli ping | grep -q PONG; then
            local end_time=$(date +%s%N)
            local duration=$(( (end_time - start_time) / 1000000 ))
            redis_times+=("$duration")
        fi
    done

    if [[ ${#redis_times[@]} -gt 0 ]]; then
        local avg=$(( $(IFS=+; echo "$((${redis_times[*]}))") / ${#redis_times[@]} ))
        echo "Redis: ping_avg=${avg}ms status=SUCCESS" >> "$db_file"
        info "  Redis ping: ${avg}ms average"
    else
        echo "Redis: ping=FAILED" >> "$db_file"
        warn "  Redis ping failed"
    fi

    log "Тест производительности базы данных завершен"
}

# Сбор системных метрик
collect_system_metrics() {
    log "Сбор системных метрик..."

    local metrics_file="$RESULTS_DIR/system-metrics.txt"
    echo "# System Metrics" > "$metrics_file"
    echo "Timestamp: $(date)" >> "$metrics_file"
    echo "" >> "$metrics_file"

    # CPU и память
    echo "=== CPU and Memory ===" >> "$metrics_file"
    top -bn1 | head -20 >> "$metrics_file"
    echo "" >> "$metrics_file"

    # Сетевые интерфейсы
    echo "=== Network Interfaces ===" >> "$metrics_file"
    ip addr show >> "$metrics_file"
    echo "" >> "$metrics_file"

    # Docker статистика
    echo "=== Docker Stats ===" >> "$metrics_file"
    docker stats --no-stream >> "$metrics_file"
    echo "" >> "$metrics_file"

    # Сетевые соединения
    echo "=== Network Connections ===" >> "$metrics_file"
    ss -tuln >> "$metrics_file"
    echo "" >> "$metrics_file"

    # Параметры ядра
    echo "=== Kernel Network Parameters ===" >> "$metrics_file"
    sysctl net.core.rmem_max net.core.wmem_max net.core.somaxconn net.ipv4.tcp_rmem net.ipv4.tcp_wmem >> "$metrics_file"

    log "Системные метрики собраны"
}

# Генерация отчета
generate_report() {
    log "Генерация отчета о производительности..."

    local report_file="$RESULTS_DIR/performance-report.md"

    cat > "$report_file" << EOF
# ERNI-KI Network Performance Test Report

**Дата тестирования**: $(date)
**Версия**: Оптимизированная сетевая архитектура

## Обзор результатов

### Состояние сервисов
\`\`\`
$(cat "$RESULTS_DIR/services-health.txt" 2>/dev/null || echo "Данные недоступны")
\`\`\`

### Латентность между сервисами
\`\`\`
$(cat "$RESULTS_DIR/internal-latency.txt" 2>/dev/null || echo "Данные недоступны")
\`\`\`

### Пропускная способность HTTP
\`\`\`
$(cat "$RESULTS_DIR/http-throughput.txt" 2>/dev/null || echo "Данные недоступны")
\`\`\`

### Производительность AI сервисов
\`\`\`
$(cat "$RESULTS_DIR/ai-performance.txt" 2>/dev/null || echo "Данные недоступны")
\`\`\`

### Производительность базы данных
\`\`\`
$(cat "$RESULTS_DIR/database-performance.txt" 2>/dev/null || echo "Данные недоступны")
\`\`\`

## Рекомендации

### Критические проблемы
- Проверьте сервисы со статусом FAILED
- Убедитесь в корректности сетевых настроек

### Оптимизации
- Латентность < 10ms между сервисами - отлично
- Латентность 10-50ms - приемлемо
- Латентность > 50ms - требует оптимизации

### Следующие шаги
1. Исправить критические проблемы
2. Оптимизировать медленные соединения
3. Повторить тестирование после изменений

---
*Отчет сгенерирован автоматически скриптом test-network-performance.sh*
EOF

    log "Отчет сохранен: $report_file"
}

# Основная функция
main() {
    log "Запуск тестирования производительности сети ERNI-KI..."

    setup_test_environment
    check_services_health

    info "Прогрев системы ($WARMUP_TIME секунд)..."
    sleep "$WARMUP_TIME"

    test_internal_latency
    test_http_throughput
    test_ai_performance
    test_database_performance
    collect_system_metrics
    generate_report

    log "Тестирование производительности завершено!"
    info "Результаты сохранены в: $RESULTS_DIR"
    info "Отчет доступен: $RESULTS_DIR/performance-report.md"
}

# Запуск основной функции
main "$@"
