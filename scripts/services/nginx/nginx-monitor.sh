#!/bin/bash

# ERNI-KI NGINX Production Monitoring Script
# Комплексный мониторинг nginx для продакшен среды

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}📊 ERNI-KI NGINX Production Monitoring${NC}"
echo "=================================================="

# Функция для проверки endpoint
test_endpoint() {
    local url=$1
    local description=$2
    local timeout=${3:-10}

    echo -n "Testing $description... "

    local start_time=$(date +%s%3N)
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time $timeout "$url" 2>/dev/null || echo "000")
    local end_time=$(date +%s%3N)
    local response_time=$((end_time - start_time))

    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}✅ OK (${response_time}ms)${NC}"
        return 0
    elif [ "$http_code" = "301" ] || [ "$http_code" = "302" ]; then
        echo -e "${YELLOW}↗️ Redirect $http_code (${response_time}ms)${NC}"
        return 0
    else
        echo -e "${RED}❌ HTTP $http_code (${response_time}ms)${NC}"
        return 1
    fi
}

# Проверка статуса контейнера
check_container_status() {
    echo -e "\n${CYAN}🐳 Container Status${NC}"
    echo "-------------------"

    local status=$(docker ps --filter "name=nginx" --format "{{.Status}}" 2>/dev/null || echo "Not found")
    local health=$(docker inspect erni-ki-nginx-1 2>/dev/null | jq -r '.[0].State.Health.Status' 2>/dev/null || echo "unknown")

    echo "Status: $status"
    echo "Health: $health"

    if [[ "$status" == *"Up"* ]]; then
        echo -e "${GREEN}✅ Container is running${NC}"
    else
        echo -e "${RED}❌ Container is not running${NC}"
        return 1
    fi
}

# Проверка производительности
check_performance() {
    echo -e "\n${CYAN}⚡ Performance Metrics${NC}"
    echo "----------------------"

    # CPU и Memory usage
    local stats=$(docker stats erni-ki-nginx-1 --no-stream --format "{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null || echo "N/A\tN/A")
    local cpu=$(echo "$stats" | cut -f1)
    local memory=$(echo "$stats" | cut -f2)

    echo "CPU Usage: $cpu"
    echo "Memory Usage: $memory"

    # Response times
    echo -e "\nResponse Times:"
    test_endpoint "http://localhost:8080/health" "HTTP Health"
    test_endpoint "https://localhost:443/health" "HTTPS Health" 15
    # RAG components
    test_endpoint "https://localhost/api/docling/health" "Docling over HTTPS" 10
    test_endpoint "https://localhost/api/searxng/search?q=test&format=json" "SearXNG API over HTTPS" 10
    test_endpoint "https://localhost/searxng/healthz" "SearXNG health over HTTPS" 5

    # Worker processes (если доступно)
    local workers=$(docker exec erni-ki-nginx-1 ls -la /proc/ 2>/dev/null | grep -E "^d.*[0-9]+$" | wc -l 2>/dev/null || echo "N/A")
    echo "Active Processes: $workers"
}

# Проверка SSL/TLS
check_ssl_tls() {
    echo -e "\n${CYAN}🔒 SSL/TLS Status${NC}"
    echo "------------------"

    # SSL certificate info
    if openssl s_client -connect localhost:443 -servername localhost </dev/null 2>/dev/null | openssl x509 -noout -dates 2>/dev/null; then
        echo -e "${GREEN}✅ SSL certificate is valid${NC}"
    else
        echo -e "${RED}❌ SSL certificate issues${NC}"
    fi

    # SSL protocols and ciphers
    echo -e "\nSSL Configuration:"
    echo | openssl s_client -connect localhost:443 -servername localhost 2>/dev/null | grep -E "(Protocol|Cipher)" || echo "Unable to retrieve SSL info"
}

# Проверка security headers
check_security_headers() {
    echo -e "\n${CYAN}🛡️ Security Headers${NC}"
    echo "--------------------"

    echo "HTTPS Headers:"
    local https_headers=$(curl -s -I -k https://localhost:443/health 2>/dev/null || echo "")

    # Проверка основных security headers
    local headers_to_check=(
        "Strict-Transport-Security"
        "X-Frame-Options"
        "X-Content-Type-Options"
        "X-XSS-Protection"
        "Referrer-Policy"
        "Content-Security-Policy"
    )

    for header in "${headers_to_check[@]}"; do
        if echo "$https_headers" | grep -qi "$header"; then
            echo -e "  ${GREEN}✅ $header${NC}"
        else
            echo -e "  ${RED}❌ $header${NC}"
        fi
    done
}

# Проверка логов на ошибки
check_logs() {
    echo -e "\n${CYAN}📋 Recent Logs Analysis${NC}"
    echo "------------------------"

    # Последние ошибки
    local error_count=$(docker logs erni-ki-nginx-1 --tail=100 2>/dev/null | grep -c -E "(error|Error|ERROR)" 2>/dev/null || echo "0")
    local warn_count=$(docker logs erni-ki-nginx-1 --tail=100 2>/dev/null | grep -c -E "(warn|Warn|WARN)" 2>/dev/null || echo "0")

    echo "Recent Errors (last 100 lines): $error_count"
    echo "Recent Warnings (last 100 lines): $warn_count"

    if [ "$error_count" -gt 0 ]; then
        echo -e "\n${RED}Recent Errors:${NC}"
        docker logs erni-ki-nginx-1 --tail=100 2>/dev/null | grep -E "(error|Error|ERROR)" | tail -5
    fi

    if [ "$warn_count" -gt 0 ]; then
        echo -e "\n${YELLOW}Recent Warnings:${NC}"
        docker logs erni-ki-nginx-1 --tail=100 2>/dev/null | grep -E "(warn|Warn|WARN)" | tail -3
    fi
}

# Проверка конфигурации
check_configuration() {
    echo -e "\n${CYAN}⚙️ Configuration Status${NC}"
    echo "------------------------"

    # Тест конфигурации
    if docker exec erni-ki-nginx-1 nginx -t 2>/dev/null; then
        echo -e "${GREEN}✅ Configuration is valid${NC}"
    else
        echo -e "${RED}❌ Configuration has errors${NC}"
        docker exec erni-ki-nginx-1 nginx -t 2>&1 | head -5
    fi

    # Версия nginx
    local version=$(docker exec erni-ki-nginx-1 nginx -v 2>&1 | cut -d' ' -f3 2>/dev/null || echo "unknown")
    echo "NGINX Version: $version"

    # HTTP/2 support
    if docker exec erni-ki-nginx-1 nginx -T 2>/dev/null | grep -q "http2"; then
        echo -e "${GREEN}✅ HTTP/2 enabled${NC}"
    else
        echo -e "${YELLOW}⚠️ HTTP/2 not detected${NC}"
    fi
}

# Проверка upstream connectivity
check_upstream() {
    echo -e "\n${CYAN}🔗 Upstream Connectivity${NC}"
    echo "-------------------------"

    # Проверка OpenWebUI
    if docker exec erni-ki-nginx-1 curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://openwebui:8080/health 2>/dev/null | grep -q "200"; then
        echo -e "${GREEN}✅ OpenWebUI upstream reachable${NC}"
    else
        echo -e "${RED}❌ OpenWebUI upstream unreachable${NC}"
    fi

    # DNS resolution test
    if docker exec erni-ki-nginx-1 nslookup openwebui 2>/dev/null >/dev/null; then
        echo -e "${GREEN}✅ DNS resolution working${NC}"
    else
        echo -e "${YELLOW}⚠️ DNS resolution issues${NC}"
    fi
}

# Генерация отчета
generate_report() {
    echo -e "\n${CYAN}📊 Summary Report${NC}"
    echo "=================="

    local total_checks=0
    local passed_checks=0

    # Подсчет результатов (упрощенная версия)
    echo "System Status:"

    # Container status
    if docker ps --filter "name=nginx" --format "{{.Status}}" 2>/dev/null | grep -q "Up"; then
        echo -e "  ${GREEN}✅ Container Running${NC}"
        ((passed_checks++))
    else
        echo -e "  ${RED}❌ Container Issues${NC}"
    fi
    ((total_checks++))

    # HTTP connectivity
    if curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:8080/health 2>/dev/null | grep -q "200"; then
        echo -e "  ${GREEN}✅ HTTP Connectivity${NC}"
        ((passed_checks++))
    else
        echo -e "  ${RED}❌ HTTP Issues${NC}"
    fi
    ((total_checks++))

    # Configuration validity
    if docker exec erni-ki-nginx-1 nginx -t 2>/dev/null; then
        echo -e "  ${GREEN}✅ Configuration Valid${NC}"
        ((passed_checks++))
    else
        echo -e "  ${RED}❌ Configuration Issues${NC}"
    fi
    ((total_checks++))

    # Overall score
    local score=$((passed_checks * 100 / total_checks))
    echo -e "\nOverall Health Score: ${score}% (${passed_checks}/${total_checks})"

    if [ $score -ge 90 ]; then
        echo -e "${GREEN}🎉 NGINX is running optimally${NC}"
    elif [ $score -ge 70 ]; then
        echo -e "${YELLOW}⚠️ NGINX has minor issues${NC}"
    else
        echo -e "${RED}🚨 NGINX needs attention${NC}"
    fi

    echo -e "\n${BLUE}💡 Recommendations:${NC}"
    echo "- Monitor logs regularly for errors"
    echo "- Check SSL certificate expiration"
    echo "- Review performance metrics"
    echo "- Update security headers as needed"
}

# Основная функция
main() {
    # Проверка, что мы в правильной директории
    if [ ! -f "compose.production.yml" ]; then
        echo -e "${RED}Error: Script must be run from ERNI-KI project root directory${NC}"
        exit 1
    fi

    # Выполнение всех проверок
    check_container_status
    check_performance
    check_ssl_tls
    check_security_headers
    check_logs
    check_configuration
    check_upstream
    generate_report

    echo -e "\n${BLUE}Monitoring completed at $(date)${NC}"
}

# Запуск основной функции
main "$@"
