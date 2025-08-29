#!/bin/bash

# ===== СКРИПТ МОНИТОРИНГА ПРОИЗВОДИТЕЛЬНОСТИ WATCHTOWER =====
# Мониторинг ресурсов, времени выполнения и влияния на систему

set -euo pipefail

# Конфигурация
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/logs/watchtower"
METRICS_FILE="$LOG_DIR/performance-metrics.json"
REPORT_FILE="$LOG_DIR/performance-report.txt"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Создание директории логов
mkdir -p "$LOG_DIR"

# Функции логирования
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

# Получение метрик контейнера
get_container_metrics() {
    local container_name="$1"
    local timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    if ! docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" "$container_name" 2>/dev/null; then
        error "Не удалось получить метрики для контейнера $container_name"
        return 1
    fi
}

# Детальные метрики в JSON формате
get_detailed_metrics() {
    local container_name="$1"
    local timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Получаем статистику контейнера
    local stats=$(docker stats --no-stream --format "{{.CPUPerc}},{{.MemUsage}},{{.NetIO}},{{.BlockIO}}" "$container_name" 2>/dev/null || echo "0.00%,0B / 0B,0B / 0B,0B / 0B")

    # Парсим статистику
    IFS=',' read -r cpu_perc mem_usage net_io block_io <<< "$stats"

    # Извлекаем числовые значения
    cpu_value=$(echo "$cpu_perc" | sed 's/%//')
    mem_used=$(echo "$mem_usage" | cut -d'/' -f1 | sed 's/[^0-9.]//g')
    mem_total=$(echo "$mem_usage" | cut -d'/' -f2 | sed 's/[^0-9.]//g')

    # Создаем JSON
    cat << EOF
{
  "timestamp": "$timestamp",
  "container": "$container_name",
  "cpu_percent": "$cpu_value",
  "memory_used_mb": "$mem_used",
  "memory_total_mb": "$mem_total",
  "network_io": "$net_io",
  "block_io": "$block_io"
}
EOF
}

# Мониторинг времени выполнения Watchtower
monitor_execution_time() {
    log "Мониторинг времени выполнения Watchtower..."

    local start_time=$(date +%s)
    local container_name="erni-ki-watchtower-1"

    # Получаем начальные метрики
    local start_metrics=$(get_detailed_metrics "$container_name")

    # Ждем завершения цикла проверки (максимум 5 минут)
    local timeout=300
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if docker logs "$container_name" --since="$start_time" 2>/dev/null | grep -q "Session done"; then
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    local end_time=$(date +%s)
    local execution_time=$((end_time - start_time))

    # Получаем конечные метрики
    local end_metrics=$(get_detailed_metrics "$container_name")

    # Сохраняем результаты
    cat << EOF >> "$METRICS_FILE"
{
  "execution_start": "$start_time",
  "execution_end": "$end_time",
  "execution_time_seconds": $execution_time,
  "start_metrics": $start_metrics,
  "end_metrics": $end_metrics
},
EOF

    success "Время выполнения: ${execution_time}s"
}

# Анализ логов Watchtower
analyze_logs() {
    log "Анализ логов Watchtower..."

    local container_name="erni-ki-watchtower-1"
    local since_time="24h"

    # Получаем логи за последние 24 часа
    local logs=$(docker logs "$container_name" --since="$since_time" 2>/dev/null || echo "")

    if [[ -z "$logs" ]]; then
        warning "Логи Watchtower недоступны"
        return 1
    fi

    # Анализируем логи
    local total_sessions=$(echo "$logs" | grep -c "Session done" || echo "0")
    local failed_updates=$(echo "$logs" | grep -c "level=error" || echo "0")
    local successful_updates=$(echo "$logs" | grep -c "updated to" || echo "0")
    local skipped_containers=$(echo "$logs" | grep -c "Skipping" || echo "0")

    # Среднее время между проверками
    local check_intervals=$(echo "$logs" | grep "Scheduled next run" | wc -l || echo "0")

    cat << EOF
=== АНАЛИЗ ЛОГОВ WATCHTOWER (24ч) ===
Всего сессий: $total_sessions
Успешных обновлений: $successful_updates
Ошибок: $failed_updates
Пропущено контейнеров: $skipped_containers
Запланированных проверок: $check_intervals
EOF
}

# Проверка влияния на производительность системы
check_system_impact() {
    log "Проверка влияния на производительность системы..."

    # Получаем общую загрузку системы
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | sed 's/,//g')
    local memory_info=$(free -m | awk 'NR==2{printf "%.1f%%", $3*100/$2}')
    local disk_usage=$(df -h / | awk 'NR==2{print $5}')

    # Проверяем количество запущенных контейнеров
    local running_containers=$(docker ps --format "table {{.Names}}" | wc -l)
    local total_containers=$(docker ps -a --format "table {{.Names}}" | wc -l)

    cat << EOF
=== ВЛИЯНИЕ НА СИСТЕМУ ===
Загрузка CPU: $load_avg
Использование памяти: $memory_info
Использование диска: $disk_usage
Запущенных контейнеров: $running_containers
Всего контейнеров: $total_containers
EOF
}

# Проверка расписания и следующего запуска
check_schedule() {
    log "Проверка расписания Watchtower..."

    local container_name="erni-ki-watchtower-1"

    # Получаем информацию о следующем запуске из логов
    local next_run=$(docker logs "$container_name" --tail=50 2>/dev/null | grep "Scheduled next run" | tail -1 | awk -F'Scheduled next run: ' '{print $2}' || echo "Не найдено")

    # Проверяем конфигурацию расписания
    local schedule_config=$(docker exec "$container_name" env | grep "WATCHTOWER_SCHEDULE" || echo "WATCHTOWER_SCHEDULE=не настроено")

    cat << EOF
=== РАСПИСАНИЕ WATCHTOWER ===
Конфигурация: $schedule_config
Следующий запуск: $next_run
EOF
}

# Генерация отчета о производительности
generate_performance_report() {
    log "Генерация отчета о производительности..."

    local timestamp=$(date +'%Y-%m-%d %H:%M:%S UTC')

    cat << EOF > "$REPORT_FILE"
===== ОТЧЕТ О ПРОИЗВОДИТЕЛЬНОСТИ WATCHTOWER =====
Дата генерации: $timestamp

$(check_system_impact)

$(analyze_logs)

$(check_schedule)

=== РЕКОМЕНДАЦИИ ===
1. Оптимальное время запуска: 03:00 UTC (минимальная нагрузка)
2. Частота проверок: Ежедневно (баланс актуальности и нагрузки)
3. Мониторинг ресурсов: Ограничение памяти 128MB, CPU 0.1 core
4. Очистка образов: Включена для экономии места
5. Критические сервисы: Исключены из автообновления

=== МЕТРИКИ КАЧЕСТВА ===
- Время выполнения: <60 секунд (цель)
- Использование памяти: <128MB (лимит)
- Влияние на CPU: <5% (цель)
- Успешность обновлений: >95% (цель)

=== СЛЕДУЮЩИЕ ШАГИ ===
1. Настроить уведомления для критических ошибок
2. Интегрировать с системой мониторинга
3. Создать процедуры отката для неудачных обновлений
4. Настроить резервное копирование перед обновлениями

EOF

    success "Отчет сохранен: $REPORT_FILE"
}

# Оптимизация конфигурации
optimize_configuration() {
    log "Анализ возможностей оптимизации..."

    local config_file="$PROJECT_DIR/env/watchtower.env"
    local suggestions=()

    # Проверяем текущую конфигурацию
    if ! grep -q "WATCHTOWER_SCHEDULE=" "$config_file"; then
        suggestions+=("Добавить расписание: WATCHTOWER_SCHEDULE=0 0 3 * * *")
    fi

    if ! grep -q "WATCHTOWER_CLEANUP=true" "$config_file"; then
        suggestions+=("Включить очистку образов: WATCHTOWER_CLEANUP=true")
    fi

    if ! grep -q "WATCHTOWER_LOG_FORMAT=json" "$config_file"; then
        suggestions+=("Использовать JSON логи: WATCHTOWER_LOG_FORMAT=json")
    fi

    if [[ ${#suggestions[@]} -gt 0 ]]; then
        warning "Рекомендации по оптимизации:"
        for suggestion in "${suggestions[@]}"; do
            echo "  - $suggestion"
        done
    else
        success "Конфигурация оптимизирована"
    fi
}

# Основная функция
main() {
    local command="${1:-monitor}"

    case "$command" in
        "monitor")
            monitor_execution_time
            ;;
        "analyze")
            analyze_logs
            ;;
        "impact")
            check_system_impact
            ;;
        "schedule")
            check_schedule
            ;;
        "report")
            generate_performance_report
            ;;
        "optimize")
            optimize_configuration
            ;;
        "full")
            log "Запуск полного мониторинга..."
            check_system_impact
            echo ""
            analyze_logs
            echo ""
            check_schedule
            echo ""
            optimize_configuration
            echo ""
            generate_performance_report
            ;;
        *)
            cat << EOF
Использование: $0 [КОМАНДА]

Команды:
    monitor   - Мониторинг времени выполнения
    analyze   - Анализ логов
    impact    - Проверка влияния на систему
    schedule  - Проверка расписания
    report    - Генерация отчета
    optimize  - Рекомендации по оптимизации
    full      - Полный анализ

Файлы:
    Метрики: $METRICS_FILE
    Отчет: $REPORT_FILE
EOF
            ;;
    esac
}

# Проверка окружения
if [[ ! -f "$PROJECT_DIR/compose.yml" ]]; then
    error "Скрипт должен быть запущен из проекта ERNI-KI"
    exit 1
fi

# Запуск
main "$@"
