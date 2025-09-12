#!/bin/bash
# Система мониторинга здоровья ERNI-KI
# Комплексный мониторинг всех сервисов с алертами и метриками

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Конфигурация
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_ROOT/.config-backup/logs"
METRICS_DIR="$PROJECT_ROOT/.config-backup/metrics"
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"
MONITORING_INTERVAL="${MONITORING_INTERVAL:-60}"

# Создание директорий
mkdir -p "$LOG_DIR" "$METRICS_DIR"

# Функции логирования
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_DIR/health-monitor.log"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1" | tee -a "$LOG_DIR/health-monitor.log"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_DIR/health-monitor.log"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_DIR/health-monitor.log"
}

info() {
    echo -e "${CYAN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_DIR/health-monitor.log"
}

# Функция отправки алертов
send_alert() {
    local severity="$1"
    local message="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Логирование алерта
    echo "{\"timestamp\":\"$timestamp\",\"severity\":\"$severity\",\"message\":\"$message\",\"service\":\"erni-ki\"}" >> "$LOG_DIR/alerts.json"

    # Отправка webhook (если настроен)
    if [[ -n "$ALERT_WEBHOOK" ]]; then
        curl -s -X POST "$ALERT_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"timestamp\":\"$timestamp\",\"severity\":\"$severity\",\"message\":\"$message\",\"service\":\"erni-ki\"}" \
            || warning "Не удалось отправить webhook алерт"
    fi
}

# Проверка статуса Docker сервисов
check_docker_services() {
    log "Проверка статуса Docker сервисов..."

    local services=(
        "auth" "backrest" "cloudflared" "db" "docling"
        "edgetts" "litellm" "mcposerver" "nginx" "ollama"
        "openwebui" "redis" "searxng" "tika" "watchtower"
    )

    local healthy_count=0
    local total_count=${#services[@]}

    for service in "${services[@]}"; do
        local status=$(docker-compose ps "$service" --format "{{.Status}}" 2>/dev/null || echo "not_found")
        local health=$(docker-compose ps "$service" --format "{{.Health}}" 2>/dev/null || echo "unknown")

        if [[ "$status" == *"Up"* ]]; then
            if [[ "$health" == "healthy" || "$health" == "" ]]; then
                success "✅ $service: работает (healthy)"
                ((healthy_count++))
            else
                warning "⚠️  $service: работает, но $health"
                send_alert "warning" "Сервис $service работает, но статус здоровья: $health"
            fi
        else
            error "❌ $service: $status"
            send_alert "critical" "Сервис $service недоступен: $status"
        fi
    done

    # Сохранение метрик
    local health_percentage=$((healthy_count * 100 / total_count))
    echo "{\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"healthy_services\":$healthy_count,\"total_services\":$total_count,\"health_percentage\":$health_percentage}" >> "$METRICS_DIR/service-health.json"

    info "Здоровых сервисов: $healthy_count/$total_count ($health_percentage%)"

    if [[ $health_percentage -lt 80 ]]; then
        send_alert "critical" "Критически низкий процент здоровых сервисов: $health_percentage%"
    elif [[ $health_percentage -lt 95 ]]; then
        send_alert "warning" "Низкий процент здоровых сервисов: $health_percentage%"
    fi
}

# Проверка использования ресурсов
check_system_resources() {
    log "Проверка использования системных ресурсов..."

    # CPU использование
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    cpu_usage=${cpu_usage%.*}  # Убираем десятичную часть

    # Память
    local memory_info=$(free | grep Mem)
    local total_mem=$(echo $memory_info | awk '{print $2}')
    local used_mem=$(echo $memory_info | awk '{print $3}')
    local memory_usage=$((used_mem * 100 / total_mem))

    # Диск
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')

    # GPU (если доступен)
    local gpu_usage="N/A"
    local gpu_memory="N/A"
    local gpu_temp="N/A"

    if command -v nvidia-smi &> /dev/null; then
        gpu_usage=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -1)
        gpu_memory=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits | head -1)
        gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits | head -1)
    fi

    # Логирование ресурсов
    info "CPU: ${cpu_usage}%, Память: ${memory_usage}%, Диск: ${disk_usage}%"
    if [[ "$gpu_usage" != "N/A" ]]; then
        info "GPU: ${gpu_usage}%, GPU Память: ${gpu_memory}, GPU Температура: ${gpu_temp}°C"
    fi

    # Сохранение метрик
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "{\"timestamp\":\"$timestamp\",\"cpu_usage\":$cpu_usage,\"memory_usage\":$memory_usage,\"disk_usage\":$disk_usage,\"gpu_usage\":\"$gpu_usage\",\"gpu_memory\":\"$gpu_memory\",\"gpu_temperature\":\"$gpu_temp\"}" >> "$METRICS_DIR/system-resources.json"

    # Алерты для ресурсов
    if [[ $cpu_usage -gt 85 ]]; then
        send_alert "warning" "Высокое использование CPU: ${cpu_usage}%"
    fi

    if [[ $memory_usage -gt 90 ]]; then
        send_alert "critical" "Критически высокое использование памяти: ${memory_usage}%"
    elif [[ $memory_usage -gt 80 ]]; then
        send_alert "warning" "Высокое использование памяти: ${memory_usage}%"
    fi

    if [[ $disk_usage -gt 90 ]]; then
        send_alert "critical" "Критически мало места на диске: ${disk_usage}%"
    elif [[ $disk_usage -gt 80 ]]; then
        send_alert "warning" "Мало места на диске: ${disk_usage}%"
    fi

    # GPU алерты
    if [[ "$gpu_temp" != "N/A" && $gpu_temp -gt 80 ]]; then
        send_alert "warning" "Высокая температура GPU: ${gpu_temp}°C"
    fi
}

# Проверка сетевых соединений
check_network_connectivity() {
    log "Проверка сетевых соединений..."

    local endpoints=(
        "http://localhost:8080/health:OpenWebUI"
        "http://localhost:11434/api/version:Ollama"
        "http://localhost:4000/health/liveliness:LiteLLM"
        "http://localhost:9898/health:Backrest"
    )

    local successful_checks=0
    local total_checks=${#endpoints[@]}

    for endpoint_info in "${endpoints[@]}"; do
        local endpoint=$(echo "$endpoint_info" | cut -d: -f1)
        local service=$(echo "$endpoint_info" | cut -d: -f2)

        if curl -s --max-time 10 "$endpoint" > /dev/null 2>&1; then
            success "✅ $service: доступен"
            ((successful_checks++))
        else
            error "❌ $service: недоступен ($endpoint)"
            send_alert "critical" "Сервис $service недоступен по адресу $endpoint"
        fi
    done

    local connectivity_percentage=$((successful_checks * 100 / total_checks))
    info "Доступных endpoints: $successful_checks/$total_checks ($connectivity_percentage%)"

    # Сохранение метрик
    echo "{\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"successful_checks\":$successful_checks,\"total_checks\":$total_checks,\"connectivity_percentage\":$connectivity_percentage}" >> "$METRICS_DIR/network-connectivity.json"
}

# Проверка логов на ошибки
check_error_logs() {
    log "Проверка логов на критические ошибки..."

    local error_count=0
    local warning_count=0

    # Проверка логов Docker контейнеров за последние 10 минут
    local containers=$(docker-compose ps --services)

    for container in $containers; do
        local errors=$(docker-compose logs --since=10m "$container" 2>/dev/null | grep -i "error\|fatal\|exception" | wc -l)
        local warnings=$(docker-compose logs --since=10m "$container" 2>/dev/null | grep -i "warning\|warn" | wc -l)

        error_count=$((error_count + errors))
        warning_count=$((warning_count + warnings))

        if [[ $errors -gt 0 ]]; then
            warning "⚠️  $container: $errors ошибок за последние 10 минут"
        fi
    done

    info "Найдено ошибок: $error_count, предупреждений: $warning_count"

    # Сохранение метрик
    echo "{\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"error_count\":$error_count,\"warning_count\":$warning_count}" >> "$METRICS_DIR/error-logs.json"

    if [[ $error_count -gt 10 ]]; then
        send_alert "warning" "Высокое количество ошибок в логах: $error_count за последние 10 минут"
    fi
}

# Генерация отчета о состоянии системы
generate_health_report() {
    local report_file="$LOG_DIR/health-report-$(date +%Y%m%d_%H%M%S).json"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    log "Генерация отчета о состоянии системы..."

    # Сбор всех метрик
    local latest_service_health=$(tail -1 "$METRICS_DIR/service-health.json" 2>/dev/null || echo "{}")
    local latest_resources=$(tail -1 "$METRICS_DIR/system-resources.json" 2>/dev/null || echo "{}")
    local latest_connectivity=$(tail -1 "$METRICS_DIR/network-connectivity.json" 2>/dev/null || echo "{}")
    local latest_errors=$(tail -1 "$METRICS_DIR/error-logs.json" 2>/dev/null || echo "{}")

    # Создание сводного отчета
    cat > "$report_file" << EOF
{
  "timestamp": "$timestamp",
  "system": "ERNI-KI",
  "version": "1.0",
  "report_type": "health_check",
  "service_health": $latest_service_health,
  "system_resources": $latest_resources,
  "network_connectivity": $latest_connectivity,
  "error_logs": $latest_errors,
  "uptime": "$(uptime -p)",
  "load_average": "$(uptime | awk -F'load average:' '{print $2}')"
}
EOF

    success "Отчет сохранен: $report_file"
}

# Основная функция мониторинга
main() {
    log "🚀 Запуск системы мониторинга ERNI-KI"

    # Проверка зависимостей
    if ! command -v docker-compose &> /dev/null; then
        error "docker-compose не найден"
        exit 1
    fi

    if ! command -v curl &> /dev/null; then
        error "curl не найден"
        exit 1
    fi

    # Выполнение проверок
    check_docker_services
    check_system_resources
    check_network_connectivity
    check_error_logs
    generate_health_report

    success "✅ Мониторинг завершен успешно"
}

# Запуск в режиме демона (если указан параметр --daemon)
if [[ "$1" == "--daemon" ]]; then
    log "🔄 Запуск в режиме демона (интервал: ${MONITORING_INTERVAL}s)"

    while true; do
        main
        sleep "$MONITORING_INTERVAL"
    done
else
    main
fi
