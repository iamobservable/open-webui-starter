#!/bin/bash
# ERNI-KI System Health Check Script
# Основан на комплексной методологии диагностики v2.0
# Автор: Альтэон Шульц (Tech Lead)

set -e

# Конфигурация
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
REPORT_FILE="diagnostic-report-${TIMESTAMP}.md"
LITELLM_TOKEN="sk-7b788d5ee69638c94477f639c91f128911bdf0e024978d4ba1dbdf678eba38bb"  # pragma: allowlist secret
REDIS_PASSWORD="ErniKiRedisSecurePassword2024"  # pragma: allowlist secret

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Счетчики
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

# Функция для логирования
log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
    ((PASSED_TESTS++))
}

error() {
    echo -e "${RED}❌ $1${NC}"
    ((FAILED_TESTS++))
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    ((WARNINGS++))
}

# Функция для тестирования
test_component() {
    local name="$1"
    local command="$2"
    local expected="$3"

    ((TOTAL_TESTS++))
    log "Testing $name..."

    if result=$(eval "$command" 2>/dev/null); then
        if [[ -n "$expected" && "$result" != *"$expected"* ]]; then
            error "$name: Unexpected result - $result"
        else
            success "$name: OK ($result)"
        fi
    else
        error "$name: FAILED"
    fi
}

# Начало диагностики
echo "========================================"
echo "🔍 ERNI-KI SYSTEM HEALTH CHECK"
echo "========================================"
echo "Timestamp: $(date)"
echo "Methodology Version: 2.0"
echo

# 1. Docker контейнеры
log "1. CHECKING DOCKER CONTAINERS..."
HEALTHY_CONTAINERS=$(docker ps --filter "name=erni-ki" --format "{{.Names}}\t{{.Status}}" | grep -c "healthy" || echo "0")
TOTAL_CONTAINERS=$(docker ps --filter "name=erni-ki" --format "{{.Names}}" | wc -l)

if [[ $HEALTHY_CONTAINERS -ge 20 ]]; then
    success "Docker Containers: $HEALTHY_CONTAINERS/$TOTAL_CONTAINERS healthy"
elif [[ $HEALTHY_CONTAINERS -ge 15 ]]; then
    warning "Docker Containers: $HEALTHY_CONTAINERS/$TOTAL_CONTAINERS healthy (some issues)"
else
    error "Docker Containers: $HEALTHY_CONTAINERS/$TOTAL_CONTAINERS healthy (critical issues)"
fi
echo

# 2. LiteLLM API
log "2. TESTING LITELLM API..."
test_component "LiteLLM Models" \
    "curl -s -H 'Authorization: Bearer $LITELLM_TOKEN' 'http://localhost:4000/v1/models' | jq -r '.data | length'" \
    ""

test_component "LiteLLM Health" \
    "curl -s 'http://localhost:4000/health'" \
    "I'm alive"

test_component "LiteLLM Chat" \
    "curl -s -X POST 'http://localhost:4000/v1/chat/completions' -H 'Authorization: Bearer $LITELLM_TOKEN' -H 'Content-Type: application/json' -d '{\"model\": \"gpt-4.1-nano-2025-04-14\", \"messages\": [{\"role\": \"user\", \"content\": \"Hi\"}], \"max_tokens\": 10}' | jq -r '.choices[0].message.content'" \
    ""
echo

# 3. SearXNG Search (FIXED: correct API path)
log "3. TESTING SEARXNG..."
test_component "SearXNG JSON API" \
    "curl -s 'http://localhost:8080/api/searxng/search?q=test&format=json' | jq -r '.results | length'" \
    ""

SEARXNG_TIME=$(curl -s -w "%{time_total}" "http://localhost:8080/api/searxng/search?q=test&format=json" -o /dev/null)
if (( $(echo "$SEARXNG_TIME < 2.0" | bc -l) )); then
    success "SearXNG Response Time: ${SEARXNG_TIME}s"
else
    warning "SearXNG Response Time: ${SEARXNG_TIME}s (slow)"
fi
echo

# 4. Redis Connection
log "4. TESTING REDIS..."
test_component "Redis Ping" \
    "docker exec erni-ki-redis-1 redis-cli -a '$REDIS_PASSWORD' ping" \
    "PONG"

test_component "Redis Write/Read" \
    "docker exec erni-ki-redis-1 redis-cli -a '$REDIS_PASSWORD' set test_health_check 'ok' && docker exec erni-ki-redis-1 redis-cli -a '$REDIS_PASSWORD' get test_health_check" \
    "ok"
echo

# 5. Docling Health (FIXED: correct API path through Nginx)
log "5. TESTING DOCLING..."
test_component "Docling Health" \
    "curl -s 'http://localhost:8080/api/docling/health' | jq -r '.status'" \
    "ok"
echo

# 6. PostgreSQL
log "6. TESTING POSTGRESQL..."
test_component "PostgreSQL Connection" \
    "docker exec erni-ki-db-1 pg_isready -U postgres" \
    "accepting connections"
echo

# 7. Ollama
log "7. TESTING OLLAMA..."
test_component "Ollama API" \
    "curl -s 'http://localhost:11434/api/tags' | jq -r '.models | length'" \
    ""
echo

# 8. External HTTPS Access
log "8. TESTING EXTERNAL HTTPS ACCESS..."
DOMAINS=("ki.erni-gruppe.ch" "diz.zone" "webui.diz.zone" "lite.diz.zone" "search.diz.zone")

for domain in "${DOMAINS[@]}"; do
    HTTP_CODE=$(curl -s -w "%{http_code}" "https://$domain" -o /dev/null --max-time 10 || echo "000")
    RESPONSE_TIME=$(curl -s -w "%{time_total}" "https://$domain" -o /dev/null --max-time 10 || echo "999")

    if [[ "$HTTP_CODE" == "200" ]]; then
        if (( $(echo "$RESPONSE_TIME < 1.0" | bc -l) )); then
            success "$domain: $HTTP_CODE (${RESPONSE_TIME}s)"
        else
            warning "$domain: $HTTP_CODE (${RESPONSE_TIME}s - slow)"
        fi
    else
        error "$domain: $HTTP_CODE (failed)"
    fi
done
echo

# 9. Интеграции
log "9. TESTING INTEGRATIONS..."
OPENWEBUI_SEARXNG=$(docker logs erni-ki-openwebui-1 --since=1h 2>/dev/null | grep -c "GET /search?q=" || echo "0")
if [[ $OPENWEBUI_SEARXNG -gt 0 ]]; then
    success "OpenWebUI → SearXNG: $OPENWEBUI_SEARXNG recent searches"
else
    warning "OpenWebUI → SearXNG: No recent searches found"
fi

REDIS_KEYS=$(docker exec erni-ki-redis-1 redis-cli -a "$REDIS_PASSWORD" dbsize 2>/dev/null || echo "0")
if [[ $REDIS_KEYS -gt 0 ]]; then
    success "Redis Cache: $REDIS_KEYS keys stored"
else
    warning "Redis Cache: Empty cache"
fi
echo

# Расчет общей оценки системы
HEALTH_SCORE=0
if [[ $TOTAL_TESTS -gt 0 ]]; then
    HEALTH_SCORE=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
fi

# Определение статуса системы
if [[ $HEALTH_SCORE -ge 90 ]]; then
    STATUS="🟢 ОТЛИЧНО"
    STATUS_COLOR=$GREEN
elif [[ $HEALTH_SCORE -ge 70 ]]; then
    STATUS="🟡 ХОРОШО"
    STATUS_COLOR=$YELLOW
elif [[ $HEALTH_SCORE -ge 50 ]]; then
    STATUS="🟠 УДОВЛЕТВОРИТЕЛЬНО"
    STATUS_COLOR=$YELLOW
else
    STATUS="🔴 КРИТИЧНО"
    STATUS_COLOR=$RED
fi

# Финальный отчет
echo "========================================"
echo "📊 DIAGNOSTIC SUMMARY"
echo "========================================"
echo -e "System Health Score: ${STATUS_COLOR}${HEALTH_SCORE}%${NC}"
echo -e "System Status: ${STATUS_COLOR}${STATUS}${NC}"
echo "Total Tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
echo -e "${RED}Failed: $FAILED_TESTS${NC}"
echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
echo "Healthy Containers: $HEALTHY_CONTAINERS/$TOTAL_CONTAINERS"
echo

# Рекомендации
if [[ $FAILED_TESTS -gt 0 ]]; then
    echo "🔧 RECOMMENDATIONS:"
    echo "- Review failed components and check logs"
    echo "- Restart problematic containers if needed"
    echo "- Check network connectivity and configurations"
fi

if [[ $WARNINGS -gt 0 ]]; then
    echo "⚠️  WARNINGS TO ADDRESS:"
    echo "- Monitor performance metrics"
    echo "- Consider optimization for slow components"
fi

echo
echo "Diagnostic completed at: $(date)"
echo "Report saved to: $REPORT_FILE"

# Сохранение отчета в файл
{
    echo "# ERNI-KI DIAGNOSTIC REPORT"
    echo "Generated: $(date)"
    echo "Methodology Version: 2.0"
    echo
    echo "## SUMMARY"
    echo "- System Health Score: ${HEALTH_SCORE}%"
    echo "- System Status: ${STATUS}"
    echo "- Total Tests: $TOTAL_TESTS"
    echo "- Passed: $PASSED_TESTS"
    echo "- Failed: $FAILED_TESTS"
    echo "- Warnings: $WARNINGS"
    echo "- Healthy Containers: $HEALTHY_CONTAINERS/$TOTAL_CONTAINERS"
    echo
    echo "## DETAILED RESULTS"
    echo "See console output for detailed test results."
    echo
    echo "Generated by: ERNI-KI Health Check Script v2.0"
} > "$REPORT_FILE"

# Возврат кода выхода
if [[ $FAILED_TESTS -eq 0 ]]; then
    exit 0
else
    exit 1
fi
