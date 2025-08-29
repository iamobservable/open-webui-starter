#!/bin/bash
# Быстрое развертывание системы мониторинга ERNI-KI
# Критический приоритет - реализация в течение 24 часов

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Конфигурация
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/tmp/erni-ki-monitoring-deployment.log"

# Функции логирования
log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${BLUE}$message${NC}"
    echo "$message" >> "$LOG_FILE" 2>/dev/null || true
}

success() {
    local message="✅ $1"
    echo -e "${GREEN}$message${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1" >> "$LOG_FILE" 2>/dev/null || true
}

warning() {
    local message="⚠️  $1"
    echo -e "${YELLOW}$message${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE" 2>/dev/null || true
}

error() {
    local message="❌ $1"
    echo -e "${RED}$message${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE" 2>/dev/null || true
}

# Проверка предварительных условий
check_prerequisites() {
    log "Проверка предварительных условий..."

    # Проверка Docker
    if ! command -v docker &> /dev/null; then
        error "Docker не установлен"
        exit 1
    fi

    # Проверка Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose не установлен"
        exit 1
    fi

    # Проверка доступности портов
    local ports=(9091 3000 9093 2020 9101 8000)
    for port in "${ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep ":$port " &> /dev/null; then
            warning "Порт $port уже используется"
        fi
    done

    # Проверка дискового пространства
    local disk_usage=$(df "$PROJECT_ROOT" | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 80 ]]; then
        error "Недостаточно места на диске: ${disk_usage}%"
        exit 1
    fi

    success "Предварительные условия выполнены"
}

# Создание необходимых директорий
create_directories() {
    log "Создание необходимых директорий..."

    local dirs=(
        "$PROJECT_ROOT/data/prometheus"
        "$PROJECT_ROOT/data/grafana"
        "$PROJECT_ROOT/data/alertmanager"
        "$PROJECT_ROOT/data/elasticsearch"
        "$PROJECT_ROOT/data/fluent-bit/db"
        "$PROJECT_ROOT/monitoring/logs/critical"
        "$PROJECT_ROOT/monitoring/logs/webhook"
        "$PROJECT_ROOT/.config-backup/logs"
    )

    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            success "Создана директория: $dir"
        fi
    done

    # Установка правильных прав доступа
    chmod 755 "$PROJECT_ROOT/data/prometheus"
    chmod 755 "$PROJECT_ROOT/data/grafana"
    chmod 755 "$PROJECT_ROOT/data/alertmanager"

    success "Директории созданы"
}

# Создание сети мониторинга
create_monitoring_network() {
    log "Создание сети мониторинга..."

    # Удаляем существующую сеть если она есть проблемы с метками
    if docker network ls | grep -q "erni-ki-monitoring"; then
        log "Удаление существующей сети erni-ki-monitoring..."
        docker network rm erni-ki-monitoring 2>/dev/null || true
    fi

    # Создаем новую сеть
    docker network create erni-ki-monitoring --driver bridge --label com.docker.compose.network=monitoring
    success "Сеть erni-ki-monitoring создана"
}

# Развертывание системы мониторинга
deploy_monitoring_stack() {
    log "Развертывание системы мониторинга..."

    cd "$PROJECT_ROOT/monitoring"

    # Запуск базовых компонентов мониторинга
    log "Запуск Prometheus, Grafana, Alertmanager..."
    docker-compose -f docker-compose.monitoring.yml up -d prometheus grafana alertmanager node-exporter

    # Ожидание готовности
    sleep 30

    # Проверка статуса
    local services=("prometheus" "grafana" "alertmanager" "node-exporter")
    for service in "${services[@]}"; do
        if docker-compose -f docker-compose.monitoring.yml ps "$service" | grep -q "Up"; then
            success "$service запущен"
        else
            error "$service не запустился"
        fi
    done
}

# Настройка критических алертов
configure_critical_alerts() {
    log "Настройка критических алертов..."

    # Проверка доступности Prometheus
    local prometheus_ready=false
    for i in {1..10}; do
        if curl -s http://localhost:9091/-/ready &> /dev/null; then
            prometheus_ready=true
            break
        fi
        log "Ожидание готовности Prometheus (попытка $i/10)..."
        sleep 10
    done

    if [[ "$prometheus_ready" == "true" ]]; then
        success "Prometheus готов"

        # Перезагрузка конфигурации алертов
        if curl -s -X POST http://localhost:9091/-/reload &> /dev/null; then
            success "Конфигурация алертов перезагружена"
        else
            warning "Не удалось перезагрузить конфигурацию алертов"
        fi
    else
        error "Prometheus не готов"
    fi
}

# Развертывание GPU мониторинга
deploy_gpu_monitoring() {
    log "Развертывание GPU мониторинга..."

    # Проверка доступности NVIDIA
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi &> /dev/null; then
            log "Запуск NVIDIA GPU Exporter..."
            cd "$PROJECT_ROOT/monitoring"
            docker-compose -f docker-compose.monitoring.yml up -d nvidia-exporter

            sleep 10

            if docker-compose -f docker-compose.monitoring.yml ps nvidia-exporter | grep -q "Up"; then
                success "NVIDIA GPU Exporter запущен"
            else
                warning "NVIDIA GPU Exporter не запустился"
            fi
        else
            warning "NVIDIA GPU недоступен"
        fi
    else
        warning "nvidia-smi не найден, пропускаем GPU мониторинг"
    fi
}

# Настройка webhook уведомлений
setup_webhook_notifications() {
    log "Настройка webhook уведомлений..."

    cd "$PROJECT_ROOT/monitoring"

    # Запуск webhook receiver
    docker-compose -f docker-compose.monitoring.yml up -d webhook-receiver

    sleep 10

    if docker-compose -f docker-compose.monitoring.yml ps webhook-receiver | grep -q "Up"; then
        success "Webhook receiver запущен"

        # Тестирование webhook
        if curl -s -f http://localhost:9093/health &> /dev/null; then
            success "Webhook receiver доступен"
        else
            warning "Webhook receiver недоступен"
        fi
    else
        error "Webhook receiver не запустился"
    fi
}

# Исправление проблемных сервисов
fix_problematic_services() {
    log "Исправление проблемных сервисов..."

    cd "$PROJECT_ROOT"

    # Проверка и исправление EdgeTTS
    log "Проверка EdgeTTS..."
    if ! curl -s -f http://localhost:5050/voices &> /dev/null; then
        warning "EdgeTTS недоступен, перезапускаем..."
        docker-compose restart edgetts
        sleep 15

        if curl -s -f http://localhost:5050/voices &> /dev/null; then
            success "EdgeTTS восстановлен"
        else
            error "EdgeTTS все еще недоступен"
        fi
    else
        success "EdgeTTS работает"
    fi

    # Проверка и исправление Docling
    log "Проверка Docling..."
    if ! curl -s -f http://localhost:5001/health &> /dev/null; then
        warning "Docling недоступен, перезапускаем..."
        docker-compose restart docling
        sleep 15

        if curl -s -f http://localhost:5001/health &> /dev/null; then
            success "Docling восстановлен"
        else
            error "Docling все еще недоступен"
        fi
    else
        success "Docling работает"
    fi
}

# Проверка системы мониторинга
verify_monitoring_system() {
    log "Проверка системы мониторинга..."

    local endpoints=(
        "http://localhost:9091/-/healthy:Prometheus"
        "http://localhost:3000/api/health:Grafana"
        "http://localhost:9093/-/healthy:Alertmanager"
        "http://localhost:9101/metrics:Node Exporter"
        "http://localhost:9093/health:Webhook Receiver"
    )

    local healthy_count=0
    local total_count=${#endpoints[@]}

    for endpoint_info in "${endpoints[@]}"; do
        local endpoint=$(echo "$endpoint_info" | cut -d: -f1)
        local service=$(echo "$endpoint_info" | cut -d: -f2)

        if curl -s -f "$endpoint" &> /dev/null; then
            success "$service доступен"
            ((healthy_count++))
        else
            error "$service недоступен ($endpoint)"
        fi
    done

    log "Результат проверки: $healthy_count/$total_count сервисов здоровы"

    if [[ $healthy_count -eq $total_count ]]; then
        success "Система мониторинга полностью функциональна"
        return 0
    else
        error "Система мониторинга работает частично"
        return 1
    fi
}

# Генерация отчета о развертывании
generate_deployment_report() {
    log "Генерация отчета о развертывании..."

    local report_file="$PROJECT_ROOT/.config-backup/monitoring-deployment-report-$(date +%Y%m%d_%H%M%S).txt"

    {
        echo "=== ОТЧЕТ О РАЗВЕРТЫВАНИИ СИСТЕМЫ МОНИТОРИНГА ERNI-KI ==="
        echo "Дата: $(date)"
        echo "Хост: $(hostname)"
        echo ""

        echo "=== СТАТУС КОМПОНЕНТОВ МОНИТОРИНГА ==="
        cd "$PROJECT_ROOT/monitoring"
        docker-compose -f docker-compose.monitoring.yml ps
        echo ""

        echo "=== ДОСТУПНОСТЬ ENDPOINTS ==="
        curl -s http://localhost:9091/-/healthy && echo "Prometheus: ✅ Healthy" || echo "Prometheus: ❌ Unhealthy"
        curl -s http://localhost:3000/api/health && echo "Grafana: ✅ Healthy" || echo "Grafana: ❌ Unhealthy"
        curl -s http://localhost:9093/-/healthy && echo "Alertmanager: ✅ Healthy" || echo "Alertmanager: ❌ Unhealthy"
        curl -s http://localhost:9101/metrics > /dev/null && echo "Node Exporter: ✅ Healthy" || echo "Node Exporter: ❌ Unhealthy"
        echo ""

        echo "=== ИСПОЛЬЗОВАНИЕ РЕСУРСОВ ==="
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep -E "(prometheus|grafana|alertmanager|node-exporter|webhook)"
        echo ""

        echo "=== СЛЕДУЮЩИЕ ШАГИ ==="
        echo "1. Откройте Grafana: http://localhost:3000 (admin/admin123)"
        echo "2. Откройте Prometheus: http://localhost:9091"
        echo "3. Откройте Alertmanager: http://localhost:9093"
        echo "4. Настройте дополнительные dashboard в Grafana"
        echo "5. Протестируйте алерты"

    } > "$report_file"

    success "Отчет сохранен: $report_file"
}

# Основная функция
main() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           ERNI-KI Monitoring System Deployment              ║"
    echo "║              Развертывание системы мониторинга              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Переход в рабочую директорию
    cd "$PROJECT_ROOT"

    # Выполнение развертывания
    check_prerequisites
    echo ""

    create_directories
    echo ""

    create_monitoring_network
    echo ""

    deploy_monitoring_stack
    echo ""

    configure_critical_alerts
    echo ""

    deploy_gpu_monitoring
    echo ""

    setup_webhook_notifications
    echo ""

    fix_problematic_services
    echo ""

    verify_monitoring_system
    echo ""

    generate_deployment_report
    echo ""

    success "Развертывание системы мониторинга завершено!"
    echo ""
    echo -e "${GREEN}🎯 Следующие шаги:${NC}"
    echo "1. Откройте Grafana: http://localhost:3000 (admin/admin123)"
    echo "2. Откройте Prometheus: http://localhost:9091"
    echo "3. Откройте Alertmanager: http://localhost:9093"
    echo "4. Запустите полную диагностику: ./scripts/health_check.sh --report"
}

# Обработка аргументов командной строки
case "${1:-}" in
    --quick)
        log "Быстрое развертывание (только основные компоненты)"
        check_prerequisites
        create_directories
        create_monitoring_network
        deploy_monitoring_stack
        verify_monitoring_system
        ;;
    --gpu-only)
        log "Развертывание только GPU мониторинга"
        deploy_gpu_monitoring
        ;;
    --fix-services)
        log "Исправление проблемных сервисов"
        fix_problematic_services
        ;;
    --verify)
        log "Проверка системы мониторинга"
        verify_monitoring_system
        ;;
    *)
        main
        ;;
esac
