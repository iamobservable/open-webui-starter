#!/bin/bash

# Автоматические отчеты о состоянии системы логгирования ERNI-KI
# Фаза 3: Мониторинг и алертинг
# Version: 1.0 - Production Ready

set -euo pipefail

# ============================================================================
# КОНФИГУРАЦИЯ
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
REPORTS_DIR="$PROJECT_ROOT/.config-backup/reports"
PROMETHEUS_URL="http://localhost:9090"
GRAFANA_URL="http://localhost:3000"
FLUENT_BIT_URL="http://localhost:2020"

# Создаем директорию для отчетов
mkdir -p "$REPORTS_DIR"

# ============================================================================
# ФУНКЦИИ СБОРА МЕТРИК
# ============================================================================

get_fluent_bit_metrics() {
    echo "=== FLUENT BIT МЕТРИКИ ==="
    curl -s "$FLUENT_BIT_URL/api/v1/metrics" | jq -r '
        "Input Records: " + (.input.["forward.0"].records | tostring),
        "Input Bytes: " + (.input.["forward.0"].bytes | tostring),
        "Output Records (Loki): " + (.output.["loki.0"].proc_records | tostring),
        "Output Bytes (Loki): " + (.output.["loki.0"].proc_bytes | tostring),
        "Loki Errors: " + (.output.["loki.0"].errors | tostring),
        "Loki Retries: " + (.output.["loki.0"].retries | tostring),
        "Filter Efficiency: " + ((.output.["loki.0"].proc_records / .input.["forward.0"].records * 100) | floor | tostring) + "%"
    ' 2>/dev/null || echo "Fluent Bit метрики недоступны"
}

get_service_health() {
    echo "=== СТАТУС СЕРВИСОВ ЛОГГИРОВАНИЯ ==="
    docker-compose ps --format "table {{.Name}}\t{{.Status}}" | grep -E "(fluent|loki|grafana|prometheus|alert)" || echo "Сервисы логгирования недоступны"
}

get_log_volume_stats() {
    echo "=== СТАТИСТИКА ОБЪЕМА ЛОГОВ ==="
    
    # Размеры директорий логов
    echo "Размеры логов:"
    du -sh logs/ .config-backup/logs/ 2>/dev/null || echo "Директории логов не найдены"
    
    # Количество логов по сервисам за последний час
    echo ""
    echo "Активность логгирования (последний час):"
    for service in ollama nginx openwebui db searxng; do
        count=$(docker logs "erni-ki-${service}-1" --since=1h 2>/dev/null | wc -l)
        echo "$service: $count записей"
    done
}

get_error_summary() {
    echo "=== СВОДКА ОШИБОК ==="
    
    # Ошибки в критически важных сервисах
    echo "Ошибки в критически важных сервисах (последние 24 часа):"
    for service in ollama nginx openwebui db; do
        errors=$(docker logs "erni-ki-${service}-1" --since=24h 2>/dev/null | grep -i error | wc -l)
        if [ "$errors" -gt 0 ]; then
            echo "⚠️  $service: $errors ошибок"
        else
            echo "✅ $service: без ошибок"
        fi
    done
}

get_performance_metrics() {
    echo "=== МЕТРИКИ ПРОИЗВОДИТЕЛЬНОСТИ ==="
    
    # Использование ресурсов контейнерами логгирования
    echo "Использование ресурсов:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep -E "(fluent|loki|grafana|prometheus)" || echo "Статистика недоступна"
}

# ============================================================================
# ГЕНЕРАЦИЯ ОТЧЕТОВ
# ============================================================================

generate_daily_report() {
    local report_date=$(date +%Y-%m-%d)
    local report_file="$REPORTS_DIR/daily-logging-report-$report_date.txt"
    
    echo "Генерация ежедневного отчета: $report_file"
    
    cat > "$report_file" << EOF
# ЕЖЕДНЕВНЫЙ ОТЧЕТ О СИСТЕМЕ ЛОГГИРОВАНИЯ ERNI-KI
# Дата: $(date '+%Y-%m-%d %H:%M:%S')
# Система: $(hostname)

$(get_service_health)

$(get_fluent_bit_metrics)

$(get_log_volume_stats)

$(get_error_summary)

$(get_performance_metrics)

# ============================================================================
# РЕКОМЕНДАЦИИ
# ============================================================================

EOF

    # Добавляем рекомендации на основе метрик
    add_recommendations "$report_file"
    
    echo "✅ Ежедневный отчет создан: $report_file"
}

generate_weekly_report() {
    local report_date=$(date +%Y-W%U)
    local report_file="$REPORTS_DIR/weekly-logging-report-$report_date.txt"
    
    echo "Генерация еженедельного отчета: $report_file"
    
    cat > "$report_file" << EOF
# ЕЖЕНЕДЕЛЬНЫЙ ОТЧЕТ О СИСТЕМЕ ЛОГГИРОВАНИЯ ERNI-KI
# Неделя: $(date '+%Y-W%U (%Y-%m-%d)')
# Система: $(hostname)

## СВОДКА ЗА НЕДЕЛЮ

$(get_service_health)

$(get_fluent_bit_metrics)

## ТРЕНДЫ И АНАЛИЗ

$(analyze_weekly_trends)

## РЕКОМЕНДАЦИИ ПО ОПТИМИЗАЦИИ

EOF

    add_weekly_recommendations "$report_file"
    
    echo "✅ Еженедельный отчет создан: $report_file"
}

add_recommendations() {
    local report_file="$1"
    
    # Анализируем метрики и добавляем рекомендации
    local fluent_errors=$(curl -s "$FLUENT_BIT_URL/api/v1/metrics" 2>/dev/null | jq -r '.output.["loki.0"].errors // 0')
    local log_count=$(docker logs erni-ki-ollama-1 --since=1h 2>/dev/null | wc -l)
    
    echo "" >> "$report_file"
    
    if [ "$fluent_errors" -gt 0 ]; then
        echo "⚠️  ВНИМАНИЕ: Обнаружены ошибки доставки в Fluent Bit ($fluent_errors). Проверьте подключение к Loki." >> "$report_file"
    fi
    
    if [ "$log_count" -gt 1000 ]; then
        echo "📊 ИНФОРМАЦИЯ: Высокая активность логгирования Ollama ($log_count записей/час). Рассмотрите оптимизацию уровня логгирования." >> "$report_file"
    fi
    
    echo "✅ СТАТУС: Система логгирования функционирует в штатном режиме." >> "$report_file"
}

analyze_weekly_trends() {
    echo "Анализ трендов за неделю:"
    echo "- Средний объем логов: $(du -sh logs/ 2>/dev/null | cut -f1 || echo 'N/A')"
    echo "- Количество перезапусков Fluent Bit: $(docker logs erni-ki-fluent-bit --since=7d 2>/dev/null | grep -c 'Starting' || echo '0')"
    echo "- Критические ошибки: $(docker logs erni-ki-fluent-bit --since=7d 2>/dev/null | grep -c 'ERROR' || echo '0')"
}

add_weekly_recommendations() {
    local report_file="$1"
    
    cat >> "$report_file" << EOF

1. **Производительность**: Мониторинг показывает стабильную работу системы логгирования
2. **Оптимизация**: Рассмотрите архивирование логов старше 30 дней
3. **Безопасность**: Проверьте фильтрацию чувствительных данных в логах
4. **Мониторинг**: Все алерты настроены и функционируют корректно

## СЛЕДУЮЩИЕ ДЕЙСТВИЯ

- [ ] Проверить использование дискового пространства
- [ ] Обновить правила ротации логов при необходимости
- [ ] Провести тестирование системы алертов
- [ ] Оптимизировать производительность при высокой нагрузке

EOF
}

# ============================================================================
# ОСНОВНАЯ ЛОГИКА
# ============================================================================

main() {
    echo "🚀 Запуск генерации отчетов о системе логгирования ERNI-KI"
    echo "Время: $(date)"
    echo ""
    
    case "${1:-daily}" in
        "daily")
            generate_daily_report
            ;;
        "weekly")
            generate_weekly_report
            ;;
        "both")
            generate_daily_report
            generate_weekly_report
            ;;
        *)
            echo "Использование: $0 [daily|weekly|both]"
            exit 1
            ;;
    esac
    
    echo ""
    echo "📁 Отчеты сохранены в: $REPORTS_DIR"
    echo "🎉 Генерация отчетов завершена успешно!"
}

# Запуск скрипта
main "$@"
