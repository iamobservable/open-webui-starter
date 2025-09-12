#!/bin/bash

# ERNI-KI Domain Monitoring Script
# Скрипт для мониторинга доступности домена ki.erni-gruppe.ch

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Конфигурация
DOMAIN="ki.erni-gruppe.ch"
LOCAL_HTTPS="https://localhost"
LOCAL_HTTP="http://localhost:8080"
TIMEOUT=10
LOG_FILE=".config-backup/monitoring/ki-erni-gruppe-ch-$(date +%Y%m%d).log"

# Функции логирования
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[$timestamp]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[$timestamp] [SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[$timestamp] [WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[$timestamp] [ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Создание директории для логов
mkdir -p "$(dirname "$LOG_FILE")"

log "🔍 Начинаем мониторинг доступности $DOMAIN..."

# Функция проверки HTTP статуса
check_http_status() {
    local url=$1
    local name=$2
    local expected_status=${3:-200}

    log "Проверка $name ($url)..."

    local start_time=$(date +%s.%N)
    local status_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout $TIMEOUT "$url" 2>/dev/null || echo "000")
    local end_time=$(date +%s.%N)
    local response_time=$(echo "$end_time - $start_time" | bc -l)

    if [ "$status_code" = "$expected_status" ]; then
        success "$name: HTTP $status_code (${response_time}s)"
        return 0
    else
        error "$name: HTTP $status_code (ожидался $expected_status) (${response_time}s)"
        return 1
    fi
}

# Функция проверки сервисов
check_service_health() {
    local service=$1
    log "Проверка статуса сервиса $service..."

    local status=$(docker-compose ps --format "table {{.Service}}\t{{.Status}}" | grep "^$service" | awk '{print $2}')

    if echo "$status" | grep -q "healthy"; then
        success "Сервис $service: $status"
        return 0
    else
        warning "Сервис $service: $status"
        return 1
    fi
}

# Основные проверки
TOTAL_CHECKS=0
FAILED_CHECKS=0

# 1. Проверка локального HTTPS доступа
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if ! check_http_status "$LOCAL_HTTPS" "Локальный HTTPS"; then
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# 2. Проверка локального HTTP доступа (порт 8080)
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if ! check_http_status "$LOCAL_HTTP" "Локальный HTTP (8080)"; then
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# 3. Проверка Cloudflare tunnel
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
if ! check_http_status "https://$DOMAIN" "Cloudflare tunnel ($DOMAIN)"; then
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# 4. Проверка health endpoint
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
log "Проверка OpenWebUI health endpoint..."
if curl -s "https://$DOMAIN/api/health" | jq -e '.status == true' >/dev/null 2>&1; then
    success "OpenWebUI health endpoint: OK"
else
    error "OpenWebUI health endpoint: FAILED"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# 5. Проверка критических сервисов
for service in nginx openwebui db ollama searxng cloudflared; do
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if ! check_service_health "$service"; then
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
done

# 6. Проверка времени отклика
log "Измерение времени отклика..."
RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" --connect-timeout $TIMEOUT "https://$DOMAIN" 2>/dev/null || echo "999")

if (( $(echo "$RESPONSE_TIME < 3.0" | bc -l) )); then
    success "Время отклика: ${RESPONSE_TIME}s (цель <3s)"
else
    warning "Время отклика: ${RESPONSE_TIME}s (превышает цель 3s)"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# 7. Проверка логов на ошибки 500
log "Проверка логов nginx на ошибки 500 за последний час..."
ERROR_500_COUNT=$(docker-compose logs nginx --since 1h | grep -c " 500 " || echo "0")

if [ "$ERROR_500_COUNT" -eq 0 ]; then
    success "Ошибки 500: не обнаружены"
else
    warning "Ошибки 500: найдено $ERROR_500_COUNT за последний час"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Итоговый отчет
echo
log "📊 Итоговый отчет мониторинга:"
echo "   Всего проверок: $TOTAL_CHECKS"
echo "   Успешных: $((TOTAL_CHECKS - FAILED_CHECKS))"
echo "   Неудачных: $FAILED_CHECKS"
echo "   Время отклика: ${RESPONSE_TIME}s"
echo "   Лог файл: $LOG_FILE"

if [ "$FAILED_CHECKS" -eq 0 ]; then
    success "🎉 Все проверки пройдены успешно! Домен $DOMAIN полностью доступен."
    exit 0
elif [ "$FAILED_CHECKS" -le 2 ]; then
    warning "⚠️ Обнаружены незначительные проблемы ($FAILED_CHECKS из $TOTAL_CHECKS)"
    exit 1
else
    error "❌ Обнаружены серьезные проблемы ($FAILED_CHECKS из $TOTAL_CHECKS)"
    exit 2
fi
