#!/bin/bash

# ===================================================================
# ERNI-KI Post-WebSocket Fix Monitor
# Мониторинг системы после исправления WebSocket проблемы
# Автор: Альтэон Шульц, Tech Lead
# Дата создания: 11 сентября 2025
# ===================================================================

echo "🔍 === ERNI-KI Post-WebSocket Fix Monitor ==="
echo "📅 Дата: $(date)"
echo "⏰ Время анализа: $(date '+%H:%M:%S')"
echo ""

# Функция для цветного вывода
print_status() {
    local status=$1
    local message=$2
    case $status in
        "SUCCESS") echo "✅ $message" ;;
        "WARNING") echo "⚠️  $message" ;;
        "ERROR") echo "❌ $message" ;;
        "INFO") echo "ℹ️  $message" ;;
    esac
}

# 1. WebSocket ошибки (критический показатель)
echo "🌐 === WEBSOCKET АНАЛИЗ ==="
websocket_errors_30m=$(docker-compose logs openwebui --since 30m 2>/dev/null | grep -c "socket.io.*400" || echo "0")
websocket_errors_1h=$(docker-compose logs openwebui --since 1h 2>/dev/null | grep -c "socket.io.*400" || echo "0")

if [ "$websocket_errors_30m" -eq 0 ]; then
    print_status "SUCCESS" "WebSocket ошибки за 30 минут: $websocket_errors_30m"
elif [ "$websocket_errors_30m" -lt 50 ]; then
    print_status "WARNING" "WebSocket ошибки за 30 минут: $websocket_errors_30m (улучшение)"
else
    print_status "ERROR" "WebSocket ошибки за 30 минут: $websocket_errors_30m (требует внимания)"
fi

echo "   📊 WebSocket ошибки за час: $websocket_errors_1h"
echo ""

# 2. SearXNG ошибки (высокий приоритет)
echo "🔍 === SEARXNG АНАЛИЗ ==="
searxng_errors_1h=$(docker-compose logs searxng --since 1h 2>/dev/null | grep -c -E "(ERROR|WARN)" || echo "0")
searxng_errors_2h=$(docker-compose logs searxng --since 2h 2>/dev/null | grep -c -E "(ERROR|WARN)" || echo "0")

if [ "$searxng_errors_1h" -lt 100 ]; then
    print_status "SUCCESS" "SearXNG ошибки за час: $searxng_errors_1h"
elif [ "$searxng_errors_1h" -lt 300 ]; then
    print_status "WARNING" "SearXNG ошибки за час: $searxng_errors_1h (умеренный уровень)"
else
    print_status "ERROR" "SearXNG ошибки за час: $searxng_errors_1h (высокий уровень)"
fi

echo "   📊 SearXNG ошибки за 2 часа: $searxng_errors_2h"
echo ""

# 3. PostgreSQL FATAL ошибки
echo "🗄️ === POSTGRESQL АНАЛИЗ ==="
postgres_fatal_1h=$(docker-compose logs db --since 1h 2>/dev/null | grep -c "FATAL" || echo "0")
postgres_errors_1h=$(docker-compose logs db --since 1h 2>/dev/null | grep -c -E "(ERROR|WARN)" || echo "0")

if [ "$postgres_fatal_1h" -eq 0 ]; then
    print_status "SUCCESS" "PostgreSQL FATAL ошибки за час: $postgres_fatal_1h"
else
    print_status "ERROR" "PostgreSQL FATAL ошибки за час: $postgres_fatal_1h"
fi

echo "   📊 PostgreSQL общие ошибки за час: $postgres_errors_1h"
echo ""

# 4. RAG производительность
echo "🚀 === RAG ПРОИЗВОДИТЕЛЬНОСТЬ ==="
echo "   🧪 Тестирование SearXNG API..."

# Тест производительности с timeout
start_time=$(date +%s.%N)
rag_result=$(timeout 10s curl -s "http://localhost:8080/searxng/search?q=test&format=json" 2>/dev/null | jq '.number_of_results' 2>/dev/null)
end_time=$(date +%s.%N)

if [ $? -eq 0 ] && [ ! -z "$rag_result" ]; then
    response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "N/A")
    if (( $(echo "$response_time < 2.0" | bc -l 2>/dev/null || echo 0) )); then
        print_status "SUCCESS" "RAG ответ: ${response_time}s, результатов: $rag_result"
    elif (( $(echo "$response_time < 5.0" | bc -l 2>/dev/null || echo 0) )); then
        print_status "WARNING" "RAG ответ: ${response_time}s, результатов: $rag_result (медленно)"
    else
        print_status "ERROR" "RAG ответ: ${response_time}s, результатов: $rag_result (очень медленно)"
    fi
else
    print_status "ERROR" "RAG тест не удался (timeout или ошибка API)"
fi
echo ""

# 5. Статус сервисов
echo "🏥 === СТАТУС СЕРВИСОВ ==="
total_services=$(docker-compose ps 2>/dev/null | grep -c "erni-ki-" || echo "0")
healthy_services=$(docker-compose ps --format "table {{.Name}}\t{{.Health}}" 2>/dev/null | grep -c "healthy" || echo "0")
unhealthy_services=$(docker-compose ps --format "table {{.Name}}\t{{.Health}}" 2>/dev/null | grep -c "unhealthy" || echo "0")

if [ "$healthy_services" -ge 26 ]; then
    print_status "SUCCESS" "Healthy сервисы: $healthy_services/$total_services"
elif [ "$healthy_services" -ge 20 ]; then
    print_status "WARNING" "Healthy сервисы: $healthy_services/$total_services"
else
    print_status "ERROR" "Healthy сервисы: $healthy_services/$total_services"
fi

if [ "$unhealthy_services" -gt 0 ]; then
    print_status "ERROR" "Unhealthy сервисы: $unhealthy_services"
fi
echo ""

# 6. Общая оценка системы
echo "📊 === ОБЩАЯ ОЦЕНКА СИСТЕМЫ ==="
total_score=0

# Подсчет баллов (максимум 100)
[ "$websocket_errors_30m" -eq 0 ] && total_score=$((total_score + 25))
[ "$websocket_errors_30m" -lt 50 ] && [ "$websocket_errors_30m" -gt 0 ] && total_score=$((total_score + 15))

[ "$searxng_errors_1h" -lt 100 ] && total_score=$((total_score + 20))
[ "$searxng_errors_1h" -lt 300 ] && [ "$searxng_errors_1h" -ge 100 ] && total_score=$((total_score + 10))

[ "$postgres_fatal_1h" -eq 0 ] && total_score=$((total_score + 15))

[ ! -z "$rag_result" ] && total_score=$((total_score + 20))

[ "$healthy_services" -ge 26 ] && total_score=$((total_score + 20))
[ "$healthy_services" -ge 20 ] && [ "$healthy_services" -lt 26 ] && total_score=$((total_score + 10))

# Итоговая оценка
if [ "$total_score" -ge 80 ]; then
    print_status "SUCCESS" "Общая оценка системы: $total_score/100 (Отлично)"
elif [ "$total_score" -ge 60 ]; then
    print_status "WARNING" "Общая оценка системы: $total_score/100 (Хорошо)"
else
    print_status "ERROR" "Общая оценка системы: $total_score/100 (Требует внимания)"
fi
echo ""

# 7. Рекомендации
echo "💡 === РЕКОМЕНДАЦИИ ==="
if [ "$websocket_errors_30m" -gt 0 ]; then
    echo "   🔧 Рекомендуется полное отключение WebSocket в nginx"
fi

if [ "$searxng_errors_1h" -gt 200 ]; then
    echo "   🔧 Требуется анализ и оптимизация SearXNG конфигурации"
fi

if [ "$postgres_fatal_1h" -gt 0 ]; then
    echo "   🔧 Необходима очистка старых данных PostgreSQL pg15"
fi

if [ "$healthy_services" -lt 25 ]; then
    echo "   🔧 Проверьте статус unhealthy сервисов"
fi

if [ "$total_score" -ge 80 ]; then
    echo "   ✅ Система работает стабильно, продолжайте мониторинг"
fi
echo ""

# 8. Сохранение результатов
echo "💾 === СОХРАНЕНИЕ РЕЗУЛЬТАТОВ ==="
report_file=".config-backup/monitoring/post-websocket-report-$(date +%Y%m%d-%H%M%S).txt"
mkdir -p .config-backup/monitoring

{
    echo "ERNI-KI Post-WebSocket Monitor Report"
    echo "Дата: $(date)"
    echo "WebSocket ошибки (30м): $websocket_errors_30m"
    echo "SearXNG ошибки (1ч): $searxng_errors_1h"
    echo "PostgreSQL FATAL (1ч): $postgres_fatal_1h"
    echo "RAG результат: $rag_result"
    echo "Healthy сервисы: $healthy_services/$total_services"
    echo "Общая оценка: $total_score/100"
} > "$report_file"

print_status "INFO" "Отчет сохранен: $report_file"
echo ""

echo "🎯 === АНАЛИЗ ЗАВЕРШЕН ==="
echo "📈 Следующий запуск рекомендуется через 1 час"
echo "🔄 Для автоматического мониторинга добавьте в crontab:"
echo "   0 * * * * cd /path/to/erni-ki && ./scripts/post-websocket-monitor.sh"
echo ""

exit 0
