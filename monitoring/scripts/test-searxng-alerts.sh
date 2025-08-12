#!/bin/bash
# Скрипт для тестирования SearXNG алертов
# Создает искусственную задержку для проверки системы мониторинга

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "🧪 Тестирование SearXNG алертов производительности"
echo "=================================================="

# Функция для логирования
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Проверка доступности SearXNG
test_searxng_availability() {
    log "Проверка доступности SearXNG API..."
    
    response=$(curl -s -w "%{http_code}" "http://localhost:8080/api/searxng/search?q=test&format=json" -o /dev/null)
    
    if [ "$response" = "200" ]; then
        log "✅ SearXNG API доступен"
        return 0
    else
        log "❌ SearXNG API недоступен (HTTP $response)"
        return 1
    fi
}

# Измерение времени отклика
measure_response_time() {
    log "Измерение времени отклика SearXNG..."
    
    for i in {1..3}; do
        start_time=$(date +%s.%N)
        curl -s "http://localhost:8080/api/searxng/search?q=test$i&format=json" > /dev/null
        end_time=$(date +%s.%N)
        
        response_time=$(echo "$end_time - $start_time" | bc)
        log "Тест $i: ${response_time}s"
        
        # Проверка превышения порога
        if (( $(echo "$response_time > 2.0" | bc -l) )); then
            log "⚠️  Время отклика превышает 2 секунды!"
        else
            log "✅ Время отклика в норме"
        fi
    done
}

# Создание искусственной задержки (для тестирования алертов)
create_artificial_delay() {
    log "Создание искусственной задержки для тестирования алертов..."
    
    # Создаем временный nginx конфиг с задержкой
    cat > /tmp/nginx-delay.conf << 'EOF'
location /api/searxng/search {
    # Искусственная задержка 3 секунды для тестирования
    access_by_lua_block {
        ngx.sleep(3)
    }
    
    proxy_pass http://searxngUpstream;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
EOF
    
    log "⚠️  Для полного тестирования алертов требуется:"
    log "   1. Настройка nginx с lua модулем"
    log "   2. Или временное изменение конфигурации SearXNG"
    log "   3. Мониторинг Prometheus метрик в течение 2-3 минут"
    
    log "Альтернативный способ - проверка текущих метрик..."
}

# Проверка Prometheus метрик
check_prometheus_metrics() {
    log "Проверка Prometheus метрик для SearXNG..."
    
    # Проверяем доступность Prometheus
    if curl -s "http://localhost:9090/api/v1/query?query=up" > /dev/null 2>&1; then
        log "✅ Prometheus доступен"
        
        # Проверяем метрики blackbox для SearXNG
        metrics=$(curl -s "http://localhost:9090/api/v1/query?query=probe_duration_seconds{job=\"blackbox-searxng-api\"}")
        
        if echo "$metrics" | grep -q "probe_duration_seconds"; then
            log "✅ Метрики SearXNG API найдены"
            
            # Извлекаем значение времени отклика
            duration=$(echo "$metrics" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "N/A")
            log "Текущее время отклика: ${duration}s"
            
        else
            log "⚠️  Метрики SearXNG API не найдены"
        fi
    else
        log "❌ Prometheus недоступен на localhost:9090"
    fi
}

# Проверка алертов в Alertmanager
check_alertmanager() {
    log "Проверка активных алертов в Alertmanager..."
    
    if curl -s "http://localhost:9093/api/v1/alerts" > /dev/null 2>&1; then
        log "✅ Alertmanager доступен"
        
        # Получаем активные алерты
        alerts=$(curl -s "http://localhost:9093/api/v1/alerts")
        searxng_alerts=$(echo "$alerts" | jq '.data[] | select(.labels.service == "searxng")' 2>/dev/null || echo "")
        
        if [ -n "$searxng_alerts" ]; then
            log "⚠️  Найдены активные SearXNG алерты:"
            echo "$searxng_alerts" | jq -r '.labels.alertname' 2>/dev/null || echo "Не удалось извлечь имена алертов"
        else
            log "✅ Активных SearXNG алертов нет"
        fi
    else
        log "❌ Alertmanager недоступен на localhost:9093"
    fi
}

# Основная функция
main() {
    log "Начало тестирования SearXNG мониторинга"
    
    # Проверка доступности
    if ! test_searxng_availability; then
        log "❌ Тестирование прервано - SearXNG недоступен"
        exit 1
    fi
    
    # Измерение производительности
    measure_response_time
    
    # Проверка метрик
    check_prometheus_metrics
    
    # Проверка алертов
    check_alertmanager
    
    log "Тестирование завершено"
    log "Для полного тестирования алертов запустите мониторинг на 5-10 минут"
}

# Запуск
main "$@"
