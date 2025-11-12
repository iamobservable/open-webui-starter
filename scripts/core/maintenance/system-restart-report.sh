#!/bin/bash

# Отчет о перезапуске ERNI-KI системы
# Автор: Альтэон Шульц (ERNI-KI Tech Lead)
# Дата: $(date '+%Y-%m-%d %H:%M:%S')

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции логирования
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка статуса всех сервисов
check_all_services() {
    log "Проверка статуса всех сервисов..."

    local services=(
        "auth"
        "backrest"
        "db"
        "edgetts"
        "litellm"
        "mcposerver"
        "nginx"
        "ollama"
        "openwebui"
        "redis"
        "searxng"
        "tika"
        "watchtower"
        "cloudflared"
    )

    local healthy_count=0
    local total_count=${#services[@]}

    echo ""
    echo "=== СТАТУС СЕРВИСОВ ==="
    printf "%-15s %-10s %-20s\n" "SERVICE" "STATUS" "HEALTH"
    echo "----------------------------------------"

    for service in "${services[@]}"; do
        local status=$(docker-compose ps "$service" --format "{{.Status}}" 2>/dev/null || echo "Not found")

        if [[ "$status" == *"healthy"* ]]; then
            printf "%-15s %-10s %-20s\n" "$service" "✅ UP" "🟢 HEALTHY"
            ((healthy_count++))
        elif [[ "$status" == *"Up"* ]]; then
            printf "%-15s %-10s %-20s\n" "$service" "✅ UP" "🟡 NO HEALTH"
            ((healthy_count++))
        elif [[ "$status" == "Not found" ]]; then
            printf "%-15s %-10s %-20s\n" "$service" "❌ DOWN" "🔴 NOT FOUND"
        else
            printf "%-15s %-10s %-20s\n" "$service" "❌ DOWN" "🔴 UNHEALTHY"
        fi
    done

    echo "----------------------------------------"
    echo "Работающих сервисов: $healthy_count/$total_count"

    if [ $healthy_count -eq $total_count ]; then
        success "Все сервисы работают корректно!"
        return 0
    else
        warning "Некоторые сервисы требуют внимания"
        return 1
    fi
}

# Проверка доступности веб-интерфейса
check_web_access() {
    log "Проверка доступности веб-интерфейса..."

    local url="https://diz.zone"
    local response=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")

    if [ "$response" = "200" ]; then
        success "Веб-интерфейс доступен: $url (HTTP $response)"
        return 0
    else
        error "Веб-интерфейс недоступен: $url (HTTP $response)"
        return 1
    fi
}

# Проверка ключевых интеграций
check_integrations() {
    log "Проверка ключевых интеграций..."

    echo ""
    echo "=== ТЕСТ ИНТЕГРАЦИЙ ==="

    # TTS интеграция
    log "Тестирование EdgeTTS..."
    if curl -s -H "Authorization: Bearer your_api_key_here" \
        http://localhost:5050/v1/audio/voices >/dev/null 2>&1; then
        success "EdgeTTS API работает"
    else
        error "EdgeTTS API не работает"
    fi

    # Ollama интеграция
    log "Тестирование Ollama..."
    if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
        success "Ollama API работает"

        # Проверка моделей
        local models=$(curl -s http://localhost:11434/api/tags | jq -r '.models | length' 2>/dev/null || echo "0")
        if [ "$models" -gt 0 ]; then
            success "Доступно моделей: $models"
        else
            warning "Модели не найдены"
        fi
    else
        error "Ollama API не работает"
    fi

    # PostgreSQL интеграция
    log "Тестирование PostgreSQL..."
    if docker-compose exec -T db pg_isready >/dev/null 2>&1; then
        success "PostgreSQL работает"
    else
        error "PostgreSQL не работает"
    fi

    # SearXNG интеграция
    log "Тестирование SearXNG..."
    if curl -s http://localhost:8080/search?q=test >/dev/null 2>&1; then
        success "SearXNG работает"
    else
        error "SearXNG не работает"
    fi
}

# Проверка ресурсов системы
check_system_resources() {
    log "Проверка ресурсов системы..."

    echo ""
    echo "=== РЕСУРСЫ СИСТЕМЫ ==="

    # CPU
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    echo "CPU Usage: ${cpu_usage}%"

    # Memory
    local mem_info=$(free -h | grep "Mem:")
    echo "Memory: $mem_info"

    # Disk
    local disk_usage=$(df -h / | tail -1 | awk '{print $5}')
    echo "Disk Usage: $disk_usage"

    # Docker
    local containers=$(docker ps | wc -l)
    echo "Running Containers: $((containers-1))"
}

# Основная функция
main() {
    echo "=================================================="
    echo "🔄 ОТЧЕТ О ПЕРЕЗАПУСКЕ ERNI-KI СИСТЕМЫ"
    echo "=================================================="
    echo "Дата: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Хост: $(hostname)"
    echo ""

    # Выполнение проверок
    local all_good=true

    if ! check_all_services; then
        all_good=false
    fi
    echo ""

    if ! check_web_access; then
        all_good=false
    fi
    echo ""

    check_integrations
    echo ""

    check_system_resources
    echo ""

    echo "=================================================="
    if [ "$all_good" = true ]; then
        success "🎉 СИСТЕМА ПОЛНОСТЬЮ ГОТОВА К РАБОТЕ!"
        echo ""
        echo "📋 Доступные сервисы:"
        echo "• OpenWebUI: https://diz.zone"
        echo "• Grafana: http://localhost:3000"
        echo "• Backrest: http://localhost:9898"
        echo "• LiteLLM: http://localhost:4000"
        echo ""
        echo "🔑 Учетные данные:"
        echo "• Email: diz-admin@proton.me"
        echo "• Пароль: testpass"
    else
        warning "⚠️ СИСТЕМА ЗАПУЩЕНА С ПРЕДУПРЕЖДЕНИЯМИ"
        echo ""
        echo "Проверьте логи проблемных сервисов:"
        echo "docker-compose logs [service-name]"
    fi
    echo "=================================================="
}

# Запуск
main "$@"
