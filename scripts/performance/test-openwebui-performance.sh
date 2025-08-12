#!/bin/bash

# ERNI-KI OpenWebUI Performance Testing Script
# Тестирует производительность и функциональность OpenWebUI

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Конфигурация
OPENWEBUI_URL="http://localhost:8080"
TIMEOUT=10
PERFORMANCE_THRESHOLD=2000  # 2 секунды в миллисекундах

echo -e "${BLUE}🚀 ERNI-KI OpenWebUI Performance Test${NC}"
echo "=================================================="

# Функция для измерения времени отклика
measure_response_time() {
    local url=$1
    local description=$2

    echo -n "Testing $description... "

    local start_time=$(date +%s%3N)
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time $TIMEOUT "$url" 2>/dev/null || echo "000")
    local end_time=$(date +%s%3N)

    local response_time=$((end_time - start_time))

    if [ "$http_code" = "200" ]; then
        if [ $response_time -lt $PERFORMANCE_THRESHOLD ]; then
            echo -e "${GREEN}✅ ${response_time}ms${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠️ ${response_time}ms (slow)${NC}"
            return 1
        fi
    else
        echo -e "${RED}❌ HTTP $http_code${NC}"
        return 2
    fi
}

# Функция для тестирования API endpoint
test_api_endpoint() {
    local endpoint=$1
    local description=$2
    local expected_content=$3

    echo -n "Testing $description... "

    local response=$(curl -s --max-time $TIMEOUT "$OPENWEBUI_URL$endpoint" 2>/dev/null || echo "ERROR")

    if [[ "$response" == *"$expected_content"* ]]; then
        echo -e "${GREEN}✅ OK${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed${NC}"
        echo "  Expected: $expected_content"
        echo "  Got: ${response:0:100}..."
        return 1
    fi
}

# Основные тесты производительности
echo -e "\n${BLUE}📊 Performance Tests${NC}"
echo "-------------------"

total_tests=0
passed_tests=0

# Тест главной страницы
((total_tests++))
if measure_response_time "$OPENWEBUI_URL/" "Main page"; then
    ((passed_tests++))
fi

# Тест API версии
((total_tests++))
if test_api_endpoint "/api/version" "Version API" "0.6.18"; then
    ((passed_tests++))
fi

# Тест health endpoint
((total_tests++))
if measure_response_time "$OPENWEBUI_URL/health" "Health check"; then
    ((passed_tests++))
fi

# Тесты интеграций
echo -e "\n${BLUE}🔗 Integration Tests${NC}"
echo "--------------------"

# Тест интеграции с Ollama
((total_tests++))
echo -n "Testing Ollama integration... "
if docker exec erni-ki-openwebui-1 curl -s --max-time 5 "http://ollama:11434/api/tags" | grep -q "models"; then
    echo -e "${GREEN}✅ OK${NC}"
    ((passed_tests++))
else
    echo -e "${RED}❌ Failed${NC}"
fi

# Тест интеграции с SearXNG
((total_tests++))
echo -n "Testing SearXNG integration... "
if docker exec erni-ki-openwebui-1 curl -s --max-time 5 "http://searxng:8080/search?q=test&format=json" | grep -q "results"; then
    echo -e "${GREEN}✅ OK${NC}"
    ((passed_tests++))
else
    echo -e "${RED}❌ Failed${NC}"
fi


# Верификация RAG цепочки (минимальная)
((total_tests++))
echo -n "Testing RAG web search via Nginx API... "
if curl -s -k --max-time 8 "https://localhost/api/searxng/search?q=test&format=json" | grep -q "results"; then
    echo -e "${GREEN}✅ OK${NC}"
    ((passed_tests++))
else
    echo -e "${YELLOW}⚠️ Not verified over HTTPS${NC}"
fi

# Тест интеграции с PostgreSQL
((total_tests++))
echo -n "Testing PostgreSQL integration... "
if docker exec erni-ki-openwebui-1 python -c "
import os, psycopg2
try:
    conn = psycopg2.connect(os.environ['DATABASE_URL'])
    conn.close()
    print('OK')
except: print('FAILED')
" | grep -q "OK"; then
    echo -e "${GREEN}✅ OK${NC}"
    ((passed_tests++))
else
    echo -e "${RED}❌ Failed${NC}"
fi

# Тест интеграции с LiteLLM
((total_tests++))
echo -n "Testing LiteLLM integration... "
if docker exec erni-ki-openwebui-1 curl -s --max-time 5 "http://litellm:4000/health/liveliness" | grep -q "alive"; then
    echo -e "${GREEN}✅ OK${NC}"
    ((passed_tests++))
else
    echo -e "${RED}❌ Failed${NC}"
fi

# Тест интеграции с Docling
((total_tests++))
echo -n "Testing Docling integration... "
if docker exec erni-ki-openwebui-1 curl -s --max-time 5 "http://nginx:8080/api/docling/health" | grep -q "ok"; then
    echo -e "${GREEN}✅ OK${NC}"
    ((passed_tests++))
else
    echo -e "${RED}❌ Failed${NC}"
fi

# Тесты безопасности
echo -e "\n${BLUE}🔒 Security Tests${NC}"
echo "-----------------"

# Тест заголовков безопасности
((total_tests++))
echo -n "Testing security headers... "
headers=$(curl -s -I "$OPENWEBUI_URL/" | grep -E "(X-Frame-Options|X-Content-Type-Options|X-XSS-Protection)")
if [[ "$headers" == *"X-Frame-Options"* && "$headers" == *"X-Content-Type-Options"* ]]; then
    echo -e "${GREEN}✅ OK${NC}"
    ((passed_tests++))
else
    echo -e "${RED}❌ Missing security headers${NC}"
fi

# Проверка ресурсов
echo -e "\n${BLUE}💾 Resource Usage${NC}"
echo "------------------"

# Использование памяти
memory_usage=$(docker stats erni-ki-openwebui-1 --no-stream --format "{{.MemUsage}}" | cut -d'/' -f1)
echo "Memory usage: $memory_usage"

# Использование CPU
cpu_usage=$(docker stats erni-ki-openwebui-1 --no-stream --format "{{.CPUPerc}}")
echo "CPU usage: $cpu_usage"

# Итоговый отчет
echo -e "\n${BLUE}📋 Test Summary${NC}"
echo "==============="
echo "Total tests: $total_tests"
echo "Passed: $passed_tests"
echo "Failed: $((total_tests - passed_tests))"

success_rate=$((passed_tests * 100 / total_tests))
echo "Success rate: $success_rate%"

if [ $success_rate -ge 90 ]; then
    echo -e "\n${GREEN}🎉 OpenWebUI performance: EXCELLENT${NC}"
    exit 0
elif [ $success_rate -ge 75 ]; then
    echo -e "\n${YELLOW}⚠️ OpenWebUI performance: GOOD${NC}"
    exit 0
else
    echo -e "\n${RED}❌ OpenWebUI performance: NEEDS ATTENTION${NC}"
    exit 1
fi
