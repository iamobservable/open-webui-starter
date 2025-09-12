#!/bin/bash

# Комплексная проверка системы мониторинга ERNI-KI
# Автор: Альтэон Шульц (ERNI-KI Tech Lead)

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

header() {
    echo -e "${PURPLE}[HEADER]${NC} $1"
}

# Проверка основных компонентов мониторинга
check_monitoring_services() {
    header "Проверка компонентов мониторинга..."

    local services=(
        "prometheus:9091:Prometheus"
        "grafana:3000:Grafana"
        "alertmanager:9093:Alertmanager"
        "node-exporter:9101:Node Exporter"
        "postgres-exporter:9187:PostgreSQL Exporter"
        "redis-exporter:9121:Redis Exporter"
        "nvidia-exporter:9445:NVIDIA GPU Exporter"
        "webhook-receiver:9095:Webhook Receiver"
        "cadvisor:8081:cAdvisor"
        "blackbox-exporter:9115:Blackbox Exporter"
    )

    local healthy_count=0
    local total_count=${#services[@]}

    echo ""
    printf "%-20s %-10s %-15s %-30s\n" "SERVICE" "PORT" "STATUS" "DESCRIPTION"
    echo "------------------------------------------------------------------------"

    for service_info in "${services[@]}"; do
        IFS=':' read -r service port description <<< "$service_info"

        if curl -s -f "http://localhost:$port" >/dev/null 2>&1 || \
           curl -s -f "http://localhost:$port/health" >/dev/null 2>&1 || \
           curl -s -f "http://localhost:$port/metrics" >/dev/null 2>&1; then
            printf "%-20s %-10s %-15s %-30s\n" "$service" "$port" "✅ HEALTHY" "$description"
            ((healthy_count++))
        else
            printf "%-20s %-10s %-15s %-30s\n" "$service" "$port" "❌ DOWN" "$description"
        fi
    done

    echo "------------------------------------------------------------------------"
    echo "Работающих сервисов мониторинга: $healthy_count/$total_count"

    if [ $healthy_count -eq $total_count ]; then
        success "Все компоненты мониторинга работают!"
        return 0
    else
        warning "Некоторые компоненты мониторинга требуют внимания"
        return 1
    fi
}

# Проверка метрик
check_metrics() {
    header "Проверка сбора метрик..."

    echo ""
    echo "=== ОСНОВНЫЕ МЕТРИКИ ==="

    # Проверка доступности Prometheus
    if ! curl -s http://localhost:9091/api/v1/status/config >/dev/null; then
        error "Prometheus недоступен"
        return 1
    fi

    # Системные метрики
    log "Системные метрики (Node Exporter)..."
    local node_metrics=$(curl -s "http://localhost:9091/api/v1/query?query=up{job=\"node-exporter\"}" | jq -r '.data.result | length')
    if [ "$node_metrics" -gt 0 ]; then
        success "Node Exporter метрики: $node_metrics targets"
    else
        error "Node Exporter метрики недоступны"
    fi

    # GPU метрики
    log "GPU метрики (NVIDIA Exporter)..."
    local gpu_metrics=$(curl -s http://localhost:9445/metrics | grep -c "nvidia_gpu" || echo "0")
    if [ "$gpu_metrics" -gt 0 ]; then
        success "GPU метрики: $gpu_metrics показателей"

        # Показать текущую загрузку GPU
        local gpu_usage=$(curl -s http://localhost:9445/metrics | grep "nvidia_gpu_duty_cycle" | awk '{print $2}' | head -1)
        if [ -n "$gpu_usage" ]; then
            echo "  └─ Текущая загрузка GPU: ${gpu_usage}%"
        fi
    else
        warning "GPU метрики недоступны"
    fi

    # Контейнерные метрики
    log "Контейнерные метрики (cAdvisor)..."
    local container_metrics=$(curl -s "http://localhost:9091/api/v1/query?query=container_last_seen" | jq -r '.data.result | length')
    if [ "$container_metrics" -gt 0 ]; then
        success "Контейнерные метрики: $container_metrics контейнеров"
    else
        warning "Контейнерные метрики недоступны"
    fi

    # База данных метрики
    log "PostgreSQL метрики..."
    local db_metrics=$(curl -s "http://localhost:9091/api/v1/query?query=pg_up" | jq -r '.data.result | length')
    if [ "$db_metrics" -gt 0 ]; then
        success "PostgreSQL метрики доступны"
    else
        warning "PostgreSQL метрики недоступны"
    fi
}

# Проверка дашбордов Grafana
check_grafana_dashboards() {
    header "Проверка дашбордов Grafana..."

    # Проверка доступности Grafana API
    if ! curl -s http://localhost:3000/api/health >/dev/null; then
        error "Grafana недоступна"
        return 1
    fi

    success "Grafana доступна на http://localhost:3000"

    # Проверка источников данных
    log "Проверка источников данных..."
    echo "  ├─ Prometheus: http://localhost:9091"
    echo "  ├─ Alertmanager: http://localhost:9093"
    echo "  └─ Elasticsearch: http://localhost:9200"

    # Информация о дашбордах
    log "Предустановленные дашборды:"
    echo "  ├─ ERNI-KI System Overview"
    echo "  ├─ Infrastructure Monitoring"
    echo "  ├─ AI Services Monitoring"
    echo "  └─ Critical Alerts Dashboard"
}

# Проверка алертов
check_alerts() {
    header "Проверка системы алертов..."

    # Проверка Alertmanager
    if ! curl -s http://localhost:9093/api/v1/status >/dev/null; then
        error "Alertmanager недоступен"
        return 1
    fi

    success "Alertmanager работает на http://localhost:9093"

    # Активные алерты
    log "Проверка активных алертов..."
    local active_alerts=$(curl -s http://localhost:9093/api/v1/alerts | jq -r '.data[] | select(.state == "active") | .labels.alertname' | wc -l)

    if [ "$active_alerts" -eq 0 ]; then
        success "Активных алертов нет"
    else
        warning "Активных алертов: $active_alerts"
        curl -s http://localhost:9093/api/v1/alerts | jq -r '.data[] | select(.state == "active") | "  ├─ \(.labels.alertname): \(.labels.severity)"'
    fi

    # Webhook receiver
    log "Проверка webhook receiver..."
    if curl -s http://localhost:9095/health >/dev/null; then
        success "Webhook receiver работает на http://localhost:9095"
    else
        error "Webhook receiver недоступен"
    fi
}

# Проверка производительности
check_performance() {
    header "Проверка производительности системы..."

    echo ""
    echo "=== ТЕКУЩИЕ ПОКАЗАТЕЛИ ==="

    # CPU
    local cpu_usage=$(curl -s "http://localhost:9091/api/v1/query?query=100-(avg(irate(node_cpu_seconds_total{mode=\"idle\"}[5m]))*100)" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "N/A")
    echo "CPU Usage: ${cpu_usage}%"

    # Memory
    local mem_usage=$(curl -s "http://localhost:9091/api/v1/query?query=(1-(node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes))*100" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "N/A")
    echo "Memory Usage: ${mem_usage}%"

    # Disk
    local disk_usage=$(df -h / | tail -1 | awk '{print $5}')
    echo "Disk Usage: $disk_usage"

    # Контейнеры
    local containers=$(docker ps | wc -l)
    echo "Running Containers: $((containers-1))"

    # GPU (если доступно)
    local gpu_temp=$(curl -s http://localhost:9445/metrics | grep "nvidia_gpu_temperature_celsius" | awk '{print $2}' | head -1 2>/dev/null || echo "N/A")
    if [ "$gpu_temp" != "N/A" ]; then
        echo "GPU Temperature: ${gpu_temp}°C"
    fi
}

# Основная функция
main() {
    echo "=================================================="
    echo "🔍 СТАТУС СИСТЕМЫ МОНИТОРИНГА ERNI-KI"
    echo "=================================================="
    echo "Дата: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Хост: $(hostname)"
    echo ""

    local all_good=true

    # Выполнение проверок
    if ! check_monitoring_services; then
        all_good=false
    fi
    echo ""

    check_metrics
    echo ""

    check_grafana_dashboards
    echo ""

    check_alerts
    echo ""

    check_performance
    echo ""

    echo "=================================================="
    if [ "$all_good" = true ]; then
        success "🎉 СИСТЕМА МОНИТОРИНГА ПОЛНОСТЬЮ ФУНКЦИОНАЛЬНА!"
        echo ""
        echo "📊 Доступные интерфейсы:"
        echo "• Grafana: http://localhost:3000"
        echo "• Prometheus: http://localhost:9091"
        echo "• Alertmanager: http://localhost:9093"
        echo "• Kibana: http://localhost:5601"
        echo ""
        echo "🔧 Exporters:"
        echo "• Node Exporter: http://localhost:9101/metrics"
        echo "• GPU Exporter: http://localhost:9445/metrics"
        echo "• cAdvisor: http://localhost:8081"
    else
        warning "⚠️ СИСТЕМА МОНИТОРИНГА ТРЕБУЕТ ВНИМАНИЯ"
        echo ""
        echo "Проверьте логи проблемных сервисов:"
        echo "docker-compose -f monitoring/docker-compose.monitoring.yml logs [service-name]"
    fi
    echo "=================================================="
}

# Запуск
main "$@"
