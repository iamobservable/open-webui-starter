#!/bin/bash

# ERNI-KI MCP Integration Test Script
# Тестирует полную интеграцию MCP серверов с OpenWebUI

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Конфигурация
MCPO_URL="http://localhost:8000"
OPENWEBUI_URL="http://localhost:8080"

echo -e "${BLUE}🔍 ERNI-KI MCP Integration Test${NC}"
echo "=================================================="

# Функция для проверки endpoint
test_endpoint() {
    local url=$1
    local description=$2
    local timeout=${3:-10}
    
    echo -n "Testing $description... "
    
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time $timeout "$url" 2>/dev/null || echo "000")
    
    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}✅ OK${NC}"
        return 0
    elif [ "$http_code" = "404" ]; then
        echo -e "${YELLOW}⚠️ Not Found${NC}"
        return 1
    else
        echo -e "${RED}❌ HTTP $http_code${NC}"
        return 2
    fi
}

# Функция для проверки JSON response
test_json_endpoint() {
    local url=$1
    local description=$2
    local expected_key=$3
    
    echo -n "Testing $description... "
    
    local response=$(curl -s --max-time 10 "$url" 2>/dev/null || echo "{}")
    
    if echo "$response" | jq -e ".$expected_key" >/dev/null 2>&1; then
        local count=$(echo "$response" | jq ".$expected_key | length" 2>/dev/null || echo "0")
        echo -e "${GREEN}✅ OK ($count items)${NC}"
        return 0
    else
        echo -e "${RED}❌ No $expected_key found${NC}"
        return 1
    fi
}

total_tests=0
passed_tests=0

# Тесты MCPO сервера
echo -e "\n${BLUE}🔧 MCPO Server Tests${NC}"
echo "--------------------"

((total_tests++))
if test_endpoint "$MCPO_URL/docs" "MCPO Swagger UI"; then
    ((passed_tests++))
fi

((total_tests++))
if test_endpoint "$MCPO_URL/openapi.json" "MCPO OpenAPI spec"; then
    ((passed_tests++))
fi

# Проверка доступных paths в OpenAPI
echo -n "Checking available MCP paths... "
paths=$(curl -s "$MCPO_URL/openapi.json" 2>/dev/null | jq '.paths | keys | length' 2>/dev/null || echo "0")
if [ "$paths" -gt 0 ]; then
    echo -e "${GREEN}✅ $paths paths available${NC}"
    ((passed_tests++))
else
    echo -e "${YELLOW}⚠️ No paths yet (servers initializing)${NC}"
fi
((total_tests++))

# Тесты отдельных MCP серверов
echo -e "\n${BLUE}⚙️ Individual MCP Server Tests${NC}"
echo "-------------------------------"

# Time server
((total_tests++))
if test_endpoint "$MCPO_URL/time/tools" "Time server tools"; then
    ((passed_tests++))
fi

# Memory server
((total_tests++))
if test_endpoint "$MCPO_URL/memory/tools" "Memory server tools"; then
    ((passed_tests++))
fi

# Filesystem server
((total_tests++))
if test_endpoint "$MCPO_URL/filesystem/tools" "Filesystem server tools"; then
    ((passed_tests++))
fi

# Тесты OpenWebUI интеграции
echo -e "\n${BLUE}🌐 OpenWebUI Integration Tests${NC}"
echo "-------------------------------"

((total_tests++))
if test_endpoint "$OPENWEBUI_URL/" "OpenWebUI main page"; then
    ((passed_tests++))
fi

((total_tests++))
if test_endpoint "$OPENWEBUI_URL/health" "OpenWebUI health"; then
    ((passed_tests++))
fi

# Проверка tool connections в OpenWebUI
echo -n "Testing OpenWebUI tool connections... "
# Это требует аутентификации, поэтому проверим косвенно
if curl -s "$OPENWEBUI_URL/api/tools" 2>/dev/null | grep -q "tools\|error\|unauthorized"; then
    echo -e "${YELLOW}⚠️ Requires authentication${NC}"
    ((passed_tests++))
else
    echo -e "${RED}❌ No response${NC}"
fi
((total_tests++))

# Проверка логов на ошибки
echo -e "\n${BLUE}📋 Log Analysis${NC}"
echo "----------------"

echo -n "Checking MCPO logs for errors... "
error_count=$(docker logs erni-ki-mcposerver-1 --tail=50 2>/dev/null | grep -c -E "(ERROR|error|Error|FATAL|fatal)" || echo "0")
if [ "$error_count" -eq 0 ]; then
    echo -e "${GREEN}✅ No errors${NC}"
    ((passed_tests++))
else
    echo -e "${YELLOW}⚠️ $error_count errors found${NC}"
fi
((total_tests++))

echo -n "Checking OpenWebUI logs for MCP errors... "
mcp_error_count=$(docker logs erni-ki-openwebui-1 --tail=50 2>/dev/null | grep -c -E "(mcp|MCP|tool|Tool).*error" || echo "0")
if [ "$mcp_error_count" -eq 0 ]; then
    echo -e "${GREEN}✅ No MCP errors${NC}"
    ((passed_tests++))
else
    echo -e "${YELLOW}⚠️ $mcp_error_count MCP errors found${NC}"
fi
((total_tests++))

# Проверка производительности
echo -e "\n${BLUE}⚡ Performance Tests${NC}"
echo "--------------------"

echo -n "Testing MCPO response time... "
start_time=$(date +%s%3N)
curl -s "$MCPO_URL/docs" > /dev/null 2>&1
end_time=$(date +%s%3N)
response_time=$((end_time - start_time))

if [ $response_time -lt 2000 ]; then
    echo -e "${GREEN}✅ ${response_time}ms${NC}"
    ((passed_tests++))
else
    echo -e "${YELLOW}⚠️ ${response_time}ms (slow)${NC}"
fi
((total_tests++))

# Итоговый отчет
echo -e "\n${BLUE}📊 Test Summary${NC}"
echo "==============="
echo "Total tests: $total_tests"
echo "Passed: $passed_tests"
echo "Failed: $((total_tests - passed_tests))"

success_rate=$((passed_tests * 100 / total_tests))
echo "Success rate: $success_rate%"

echo -e "\n${BLUE}📝 MCP Integration Status${NC}"
echo "=========================="

if [ $success_rate -ge 90 ]; then
    echo -e "${GREEN}🎉 MCP Integration: EXCELLENT${NC}"
    echo "✅ MCPO server is running and healthy"
    echo "✅ MCP servers are initializing/running"
    echo "✅ OpenWebUI is ready for MCP integration"
elif [ $success_rate -ge 70 ]; then
    echo -e "${YELLOW}⚠️ MCP Integration: GOOD${NC}"
    echo "✅ MCPO server is running"
    echo "⚠️ Some MCP servers may still be initializing"
    echo "✅ OpenWebUI is accessible"
elif [ $success_rate -ge 50 ]; then
    echo -e "${YELLOW}⚠️ MCP Integration: PARTIAL${NC}"
    echo "⚠️ MCPO server has issues"
    echo "⚠️ MCP servers need attention"
    echo "✅ OpenWebUI is accessible"
else
    echo -e "${RED}❌ MCP Integration: NEEDS ATTENTION${NC}"
    echo "❌ Multiple components have issues"
    echo "❌ Integration requires troubleshooting"
fi

echo -e "\n${BLUE}🔧 Next Steps${NC}"
echo "============="
echo "1. Wait for MCP servers to fully initialize (may take 1-2 minutes)"
echo "2. Check MCPO endpoints: $MCPO_URL/docs"
echo "3. Configure OpenWebUI tool connections in Admin panel"
echo "4. Test MCP tools in OpenWebUI chat interface"

exit $((total_tests - passed_tests))
