#!/bin/bash

# ============================================================================
# ERNI-KI LOG MONITORING SCRIPT
# Автоматизированный мониторинг размеров логов и производительности системы
# Создан: 2025-09-18 в рамках улучшения системы логгирования
# ============================================================================

set -euo pipefail

# Конфигурация
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
ALERT_THRESHOLD_GB=1
CRITICAL_THRESHOLD_GB=5
WEBHOOK_URL="${LOG_MONITORING_WEBHOOK_URL:-}"
COMPOSE_FILE="$PROJECT_ROOT/compose.yml"

# Цвета для вывода
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция логгирования
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Функция отправки webhook уведомлений
send_webhook() {
    local message="$1"
    local severity="${2:-info}"

    if [[ -n "$WEBHOOK_URL" ]]; then
        curl -s -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"🔍 ERNI-KI Log Monitor: $message\", \"severity\":\"$severity\"}" \
            >/dev/null 2>&1 || warn "Failed to send webhook notification"
    fi
}

# Функция проверки размеров логов Docker контейнеров
check_docker_logs() {
    log "Проверка размеров логов Docker контейнеров..."

    local total_size=0
    local alerts=()

    while IFS= read -r container; do
        if [[ -n "$container" ]]; then
            local log_file="/var/lib/docker/containers/$container/$container-json.log"
            if [[ -f "$log_file" ]]; then
                local size_bytes=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo 0)
                local size_mb=$((size_bytes / 1024 / 1024))
                total_size=$((total_size + size_mb))

                if [[ $size_mb -gt 100 ]]; then
                    local container_name=$(docker inspect --format='{{.Name}}' "$container" 2>/dev/null | sed 's/^\/*//' || echo "unknown")
                    alerts+=("$container_name: ${size_mb}MB")
                fi
            fi
        fi
    done < <(docker ps -q)

    local total_gb=$((total_size / 1024))

    echo "📊 Общий размер логов Docker: ${total_gb}GB (${total_size}MB)"

    if [[ $total_gb -gt $CRITICAL_THRESHOLD_GB ]]; then
        error "КРИТИЧЕСКИЙ уровень использования логов: ${total_gb}GB > ${CRITICAL_THRESHOLD_GB}GB"
        send_webhook "🚨 КРИТИЧЕСКИЙ уровень логов: ${total_gb}GB" "critical"
        return 2
    elif [[ $total_gb -gt $ALERT_THRESHOLD_GB ]]; then
        warn "Превышен порог предупреждения: ${total_gb}GB > ${ALERT_THRESHOLD_GB}GB"
        send_webhook "⚠️ Превышен порог логов: ${total_gb}GB" "warning"
        return 1
    else
        success "Размер логов в норме: ${total_gb}GB"
        return 0
    fi
}

# Функция проверки производительности Fluent Bit
check_fluent_bit_performance() {
    log "Проверка производительности Fluent Bit..."

    local container_name="erni-ki-fluent-bit"

    # Проверка CPU и памяти
    local stats=$(docker stats --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}" "$container_name" 2>/dev/null || echo "N/A	N/A")
    local cpu_percent=$(echo "$stats" | tail -n1 | awk '{print $1}' | sed 's/%//')
    local mem_usage=$(echo "$stats" | tail -n1 | awk '{print $2}')

    echo "📈 Fluent Bit производительность:"
    echo "   CPU: ${cpu_percent}%"
    echo "   Memory: $mem_usage"

    # Проверка метрик через API
    local metrics_response=$(curl -s "http://localhost:2020/api/v1/metrics" 2>/dev/null || echo "{}")
    local input_records=$(echo "$metrics_response" | jq -r '.input.forward.records // 0' 2>/dev/null || echo "0")
    local output_records=$(echo "$metrics_response" | jq -r '.output.loki.proc_records // 0' 2>/dev/null || echo "0")

    echo "   Input records: $input_records"
    echo "   Output records: $output_records"

    # Проверка ошибок за последний час
    local error_count=$(docker logs "$container_name" --since 1h 2>/dev/null | grep -c -E "(ERROR|error)" || echo "0")
    echo "   Errors (1h): $error_count"

    if [[ "$error_count" -gt 50 ]]; then
        warn "Высокое количество ошибок в Fluent Bit: $error_count за час"
        send_webhook "⚠️ Fluent Bit errors: $error_count/hour" "warning"
        return 1
    else
        success "Fluent Bit работает стабильно"
        return 0
    fi
}

# Функция проверки доступности Loki API
check_loki_api() {
    log "Проверка доступности Loki API..."

    # Проверка локального API
    local local_status=$(curl -s -o /dev/null -w "%{http_code}" -H "X-Scope-OrgID: erni-ki" "http://localhost:3100/ready" 2>/dev/null || echo "000")

    # Проверка API через nginx
    local nginx_status=$(curl -k -s -o /dev/null -w "%{http_code}" -H "X-Scope-OrgID: erni-ki" "https://localhost/loki/api/v1/labels" 2>/dev/null || echo "000")

    echo "🔗 Loki API статус:"
    echo "   Локальный API: $local_status"
    echo "   Nginx proxy: $nginx_status"

    if [[ "$local_status" == "200" && "$nginx_status" == "200" ]]; then
        success "Loki API полностью доступен"
        return 0
    else
        error "Проблемы с доступностью Loki API"
        send_webhook "🚨 Loki API недоступен (local: $local_status, nginx: $nginx_status)" "critical"
        return 1
    fi
}

# Функция очистки старых логов
cleanup_old_logs() {
    log "Очистка старых логов..."

    local cleaned_files=0

    # Очистка логов старше 7 дней в директории logs/
    if [[ -d "$LOG_DIR" ]]; then
        while IFS= read -r -d '' file; do
            rm -f "$file"
            ((cleaned_files++))
        done < <(find "$LOG_DIR" -name "*.log" -type f -mtime +7 -print0 2>/dev/null)
    fi

    # Ротация логов Docker (если размер критический)
    local total_size_gb=$(check_docker_logs | grep "Общий размер" | awk '{print $5}' | sed 's/GB.*//' || echo "0")

    if [[ "${total_size_gb:-0}" -gt $CRITICAL_THRESHOLD_GB ]]; then
        log "Принудительная ротация логов Docker..."
        docker system prune -f --volumes >/dev/null 2>&1 || warn "Не удалось выполнить docker system prune"
    fi

    success "Очищено файлов: $cleaned_files"
}

# Функция генерации отчета
generate_report() {
    local timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
    local report_file="$LOG_DIR/log-monitoring-report-$timestamp.json"

    log "Генерация отчета: $report_file"

    # Создание директории если не существует
    mkdir -p "$LOG_DIR"

    # Сбор данных для отчета
    local docker_log_check=$(check_docker_logs 2>&1)
    local fluent_bit_check=$(check_fluent_bit_performance 2>&1)
    local loki_api_check=$(check_loki_api 2>&1)

    # Создание JSON отчета
    cat > "$report_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "version": "1.0",
  "system": "ERNI-KI",
  "checks": {
    "docker_logs": {
      "output": $(echo "$docker_log_check" | jq -Rs .)
    },
    "fluent_bit": {
      "output": $(echo "$fluent_bit_check" | jq -Rs .)
    },
    "loki_api": {
      "output": $(echo "$loki_api_check" | jq -Rs .)
    }
  },
  "thresholds": {
    "alert_gb": $ALERT_THRESHOLD_GB,
    "critical_gb": $CRITICAL_THRESHOLD_GB
  }
}
EOF

    success "Отчет сохранен: $report_file"
}

# Основная функция
main() {
    echo "============================================================================"
    echo "🔍 ERNI-KI LOG MONITORING - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================================================"

    local exit_code=0

    # Проверка Docker логов
    check_docker_logs || exit_code=$?
    echo

    # Проверка Fluent Bit
    check_fluent_bit_performance || exit_code=$?
    echo

    # Проверка Loki API
    check_loki_api || exit_code=$?
    echo

    # Очистка при необходимости
    if [[ $exit_code -gt 1 ]]; then
        cleanup_old_logs
        echo
    fi

    # Генерация отчета
    generate_report
    echo

    # Итоговый статус
    case $exit_code in
        0)
            success "✅ Все проверки пройдены успешно"
            send_webhook "✅ Log monitoring: все системы в норме" "info"
            ;;
        1)
            warn "⚠️ Обнаружены предупреждения"
            ;;
        2)
            error "🚨 Обнаружены критические проблемы"
            ;;
    esac

    echo "============================================================================"
    exit $exit_code
}

# Запуск скрипта
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
