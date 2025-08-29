#!/bin/bash

# Circuit Breaker Monitor для системы логгирования ERNI-KI
# Фаза 3: Мониторинг и алертинг - предотвращение каскадных сбоев
# Version: 1.0 - Production Ready

set -euo pipefail

# ============================================================================
# КОНФИГУРАЦИЯ
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FLUENT_BIT_URL="http://localhost:2020"
LOKI_URL="http://localhost:3100"
PROMETHEUS_URL="http://localhost:9090"

# Пороги для circuit breaker
ERROR_THRESHOLD=10          # Максимум ошибок за 5 минут
RETRY_THRESHOLD=50          # Максимум retry за 5 минут
BUFFER_THRESHOLD=80         # Максимальное заполнение буфера в %
RESPONSE_TIME_THRESHOLD=5   # Максимальное время ответа в секундах

# ============================================================================
# ФУНКЦИИ МОНИТОРИНГА
# ============================================================================

check_fluent_bit_health() {
    echo "=== ПРОВЕРКА ЗДОРОВЬЯ FLUENT BIT ==="
    
    # Проверяем доступность API
    if ! curl -s --max-time 5 "$FLUENT_BIT_URL/api/v1/health" > /dev/null; then
        echo "❌ Fluent Bit API недоступен"
        return 1
    fi
    
    # Получаем метрики
    local metrics=$(curl -s --max-time 5 "$FLUENT_BIT_URL/api/v1/metrics" 2>/dev/null || echo '{}')
    
    # Проверяем ошибки
    local errors=$(echo "$metrics" | jq -r '.output.["loki.0"].errors // 0')
    local retries=$(echo "$metrics" | jq -r '.output.["loki.0"].retries // 0')
    
    echo "Ошибки: $errors (порог: $ERROR_THRESHOLD)"
    echo "Повторы: $retries (порог: $RETRY_THRESHOLD)"
    
    # Circuit breaker логика
    if [ "$errors" -gt "$ERROR_THRESHOLD" ]; then
        echo "🔴 CIRCUIT BREAKER: Превышен порог ошибок ($errors > $ERROR_THRESHOLD)"
        trigger_circuit_breaker "errors" "$errors"
        return 1
    fi
    
    if [ "$retries" -gt "$RETRY_THRESHOLD" ]; then
        echo "🟡 WARNING: Высокое количество повторов ($retries > $RETRY_THRESHOLD)"
        trigger_warning "retries" "$retries"
    fi
    
    echo "✅ Fluent Bit работает в штатном режиме"
    return 0
}

check_loki_health() {
    echo "=== ПРОВЕРКА ЗДОРОВЬЯ LOKI ==="
    
    # Проверяем готовность Loki
    local start_time=$(date +%s)
    if ! curl -s --max-time "$RESPONSE_TIME_THRESHOLD" "$LOKI_URL/ready" > /dev/null; then
        echo "❌ Loki недоступен или медленно отвечает"
        trigger_circuit_breaker "loki_unavailable" "timeout"
        return 1
    fi
    local end_time=$(date +%s)
    local response_time=$((end_time - start_time))
    
    echo "Время ответа Loki: ${response_time}s (порог: ${RESPONSE_TIME_THRESHOLD}s)"
    
    if [ "$response_time" -gt "$RESPONSE_TIME_THRESHOLD" ]; then
        echo "🟡 WARNING: Медленный ответ Loki (${response_time}s > ${RESPONSE_TIME_THRESHOLD}s)"
        trigger_warning "loki_slow" "$response_time"
    fi
    
    echo "✅ Loki работает в штатном режиме"
    return 0
}

check_system_resources() {
    echo "=== ПРОВЕРКА СИСТЕМНЫХ РЕСУРСОВ ==="
    
    # Проверяем использование диска
    local disk_usage=$(df -h data/logs-optimized 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//' || echo "0")
    echo "Использование диска для логов: ${disk_usage}%"
    
    if [ "$disk_usage" -gt 90 ]; then
        echo "🔴 CIRCUIT BREAKER: Критическое заполнение диска (${disk_usage}% > 90%)"
        trigger_circuit_breaker "disk_full" "$disk_usage"
        return 1
    elif [ "$disk_usage" -gt 80 ]; then
        echo "🟡 WARNING: Высокое использование диска (${disk_usage}% > 80%)"
        trigger_warning "disk_usage" "$disk_usage"
    fi
    
    # Проверяем память контейнеров логгирования
    local fluent_memory=$(docker stats --no-stream --format "{{.MemPerc}}" erni-ki-fluent-bit 2>/dev/null | sed 's/%//' || echo "0")
    echo "Использование памяти Fluent Bit: ${fluent_memory}%"
    
    if [ "${fluent_memory%.*}" -gt 80 ]; then
        echo "🟡 WARNING: Высокое использование памяти Fluent Bit (${fluent_memory}% > 80%)"
        trigger_warning "memory_usage" "$fluent_memory"
    fi
    
    echo "✅ Системные ресурсы в норме"
    return 0
}

# ============================================================================
# CIRCUIT BREAKER ДЕЙСТВИЯ
# ============================================================================

trigger_circuit_breaker() {
    local reason="$1"
    local value="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "🔴 CIRCUIT BREAKER АКТИВИРОВАН: $reason = $value"
    
    # Логируем событие
    echo "[$timestamp] CIRCUIT_BREAKER_TRIGGERED: reason=$reason value=$value" >> "$PROJECT_ROOT/.config-backup/logs/circuit-breaker.log"
    
    # Уведомляем через webhook (если настроен)
    if command -v curl > /dev/null; then
        curl -s -X POST "http://localhost:9095/webhook/circuit-breaker" \
            -H "Content-Type: application/json" \
            -d "{\"reason\":\"$reason\",\"value\":\"$value\",\"timestamp\":\"$timestamp\",\"severity\":\"critical\"}" \
            > /dev/null 2>&1 || true
    fi
    
    # Применяем защитные меры
    case "$reason" in
        "errors"|"loki_unavailable")
            echo "Применяем защитные меры: переключение на локальное хранение логов"
            enable_local_fallback
            ;;
        "disk_full")
            echo "Применяем защитные меры: экстренная очистка старых логов"
            emergency_log_cleanup
            ;;
    esac
}

trigger_warning() {
    local reason="$1"
    local value="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "🟡 WARNING: $reason = $value"
    
    # Логируем предупреждение
    echo "[$timestamp] WARNING: reason=$reason value=$value" >> "$PROJECT_ROOT/.config-backup/logs/circuit-breaker.log"
    
    # Уведомляем через webhook
    if command -v curl > /dev/null; then
        curl -s -X POST "http://localhost:9095/webhook/warning" \
            -H "Content-Type: application/json" \
            -d "{\"reason\":\"$reason\",\"value\":\"$value\",\"timestamp\":\"$timestamp\",\"severity\":\"warning\"}" \
            > /dev/null 2>&1 || true
    fi
}

enable_local_fallback() {
    echo "Включение локального fallback режима для логов..."
    
    # Создаем временную конфигурацию с локальным выводом
    local fallback_config="$PROJECT_ROOT/conf/fluent-bit/fluent-bit-fallback.conf"
    
    # Копируем основную конфигурацию и модифицируем
    cp "$PROJECT_ROOT/conf/fluent-bit/fluent-bit.conf" "$fallback_config"
    
    # Добавляем локальный output
    cat >> "$fallback_config" << EOF

# EMERGENCY FALLBACK OUTPUT - Circuit Breaker активирован
[OUTPUT]
    Name        file
    Match       *
    Path        /var/log/emergency
    File        emergency-logs.txt
    Format      json_lines

EOF
    
    echo "✅ Локальный fallback режим настроен"
}

emergency_log_cleanup() {
    echo "Выполнение экстренной очистки логов..."
    
    # Архивируем и удаляем старые логи
    find "$PROJECT_ROOT/data/logs-optimized" -name "*.log" -mtime +7 -exec gzip {} \; 2>/dev/null || true
    find "$PROJECT_ROOT/data/logs-optimized" -name "*.gz" -mtime +30 -delete 2>/dev/null || true
    
    # Очищаем Docker логи
    docker system prune -f --volumes > /dev/null 2>&1 || true
    
    echo "✅ Экстренная очистка логов завершена"
}

# ============================================================================
# ОСНОВНАЯ ЛОГИКА
# ============================================================================

main() {
    echo "🔍 Запуск Circuit Breaker Monitor для системы логгирования ERNI-KI"
    echo "Время: $(date)"
    echo ""
    
    local overall_status=0
    
    # Создаем директорию для логов мониторинга
    mkdir -p "$PROJECT_ROOT/.config-backup/logs"
    
    # Проверяем все компоненты
    check_fluent_bit_health || overall_status=1
    echo ""
    
    check_loki_health || overall_status=1
    echo ""
    
    check_system_resources || overall_status=1
    echo ""
    
    if [ $overall_status -eq 0 ]; then
        echo "🎉 Все системы логгирования работают в штатном режиме"
    else
        echo "⚠️  Обнаружены проблемы в системе логгирования - применены защитные меры"
    fi
    
    return $overall_status
}

# Запуск мониторинга
main "$@"
