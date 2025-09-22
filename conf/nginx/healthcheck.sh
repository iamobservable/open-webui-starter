#!/bin/bash
# Nginx Enhanced Healthcheck Script
# Проверяет не только HTTP статус, но и подключения к upstream серверам
# Автор: ERNI-KI System
# Дата: 2025-09-22

set -e

# Конфигурация
NGINX_PORT=80
NGINX_SSL_PORT=443
NGINX_API_PORT=8080
TIMEOUT=5
MAX_RETRIES=2

# Цвета для логирования
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция логирования
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] HEALTHCHECK:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] HEALTHCHECK ERROR:${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] HEALTHCHECK WARNING:${NC} $1" >&2
}

# Функция проверки HTTP статуса
check_http_status() {
    local url=$1
    local expected_code=${2:-200}
    local description=$3

    log "Проверка $description: $url"

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout $TIMEOUT --max-time $TIMEOUT "$url" 2>/dev/null || echo "000")

    if [[ "$http_code" == "$expected_code" ]]; then
        log "✅ $description: HTTP $http_code"
        return 0
    else
        error "❌ $description: HTTP $http_code (ожидался $expected_code)"
        return 1
    fi
}

# Функция проверки TCP подключения
check_tcp_connection() {
    local host=$1
    local port=$2
    local description=$3

    log "Проверка TCP подключения: $description ($host:$port)"

    if timeout $TIMEOUT bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
        log "✅ $description: TCP подключение успешно"
        return 0
    else
        error "❌ $description: TCP подключение не удалось"
        return 1
    fi
}

# Функция проверки DNS резолюции
check_dns_resolution() {
    local hostname=$1
    local description=$2

    log "Проверка DNS резолюции: $description ($hostname)"

    local ip
    ip=$(getent hosts "$hostname" 2>/dev/null | awk '{print $1}' | head -1)

    if [[ -n "$ip" && "$ip" != "127.0.0.1" ]]; then
        log "✅ $description: DNS резолюция успешна ($hostname -> $ip)"
        return 0
    else
        error "❌ $description: DNS резолюция не удалась"
        return 1
    fi
}

# Функция проверки upstream сервера
check_upstream_server() {
    local hostname=$1
    local port=$2
    local service_name=$3
    local retry_count=0

    log "Проверка upstream сервера: $service_name"

    # Проверка DNS резолюции
    if ! check_dns_resolution "$hostname" "$service_name DNS"; then
        return 1
    fi

    # Проверка TCP подключения с повторными попытками
    while [[ $retry_count -lt $MAX_RETRIES ]]; do
        if check_tcp_connection "$hostname" "$port" "$service_name TCP"; then
            return 0
        fi

        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $MAX_RETRIES ]]; then
            warning "Повторная попытка $retry_count/$MAX_RETRIES для $service_name"
            sleep 1
        fi
    done

    error "❌ $service_name: Все попытки подключения не удались"
    return 1
}

# Основная функция проверки
main() {
    log "🔍 Запуск расширенной проверки здоровья nginx"

    local failed_checks=0

    # 1. Проверка основных портов nginx
    log "📡 Проверка портов nginx"

    if ! check_http_status "http://localhost:$NGINX_PORT/nginx_status" 200 "Nginx Status Page"; then
        ((failed_checks++))
    fi

    if ! check_http_status "http://localhost:$NGINX_API_PORT/health" 200 "Nginx API Health"; then
        ((failed_checks++))
    fi

    # 2. Проверка критических upstream серверов
    log "🔗 Проверка upstream серверов"

    # OpenWebUI - критический сервис
    if ! check_upstream_server "openwebui" 8080 "OpenWebUI"; then
        ((failed_checks++))
    fi

    # SearXNG - критический для RAG
    if ! check_upstream_server "searxng" 8080 "SearXNG"; then
        ((failed_checks++))
    fi

    # Ollama - критический AI сервис
    if ! check_upstream_server "ollama" 11434 "Ollama"; then
        ((failed_checks++))
    fi

    # PostgreSQL - критическая база данных
    if ! check_upstream_server "db" 5432 "PostgreSQL"; then
        ((failed_checks++))
    fi

    # 3. Проверка функциональности proxy
    log "🔄 Проверка функциональности proxy"

    # Проверка проксирования к OpenWebUI
    if ! check_http_status "http://localhost:$NGINX_API_PORT/" 200 "OpenWebUI Proxy"; then
        ((failed_checks++))
    fi

    # Проверка проксирования к SearXNG
    if ! check_http_status "http://localhost:$NGINX_API_PORT/searxng/" 200 "SearXNG Proxy"; then
        ((failed_checks++))
    fi

    # Итоговая оценка
    if [[ $failed_checks -eq 0 ]]; then
        log "✅ Все проверки пройдены успешно! Nginx здоров."
        exit 0
    elif [[ $failed_checks -le 2 ]]; then
        warning "⚠️  Обнаружены незначительные проблемы ($failed_checks), но nginx функционален"
        exit 0
    else
        error "❌ Критические проблемы обнаружены ($failed_checks). Требуется перезапуск nginx."
        exit 1
    fi
}

# Запуск основной функции
main "$@"
