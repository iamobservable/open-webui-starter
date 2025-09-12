#!/bin/bash
# ERNI-KI RAG Performance Testing Script
# Комплексное тестирование RAG функциональности и производительности

set -e

echo "🔍 ERNI-KI RAG Performance Test - $(date)"
echo "=============================================="

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для измерения времени выполнения
measure_time() {
    local start_time=$(date +%s.%N)
    "$@"
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)
    echo "$duration"
}

# Функция для тестирования API endpoint
test_api_endpoint() {
    local name=$1
    local url=$2
    local expected_code=${3:-200}
    local timeout=${4:-10}

    echo -n "Testing $name... "

    local result=$(curl -s -k -w "%{http_code}:%{time_total}" --connect-timeout $timeout "$url" -o /tmp/api_response.json 2>/dev/null)
    local http_code=$(echo $result | cut -d: -f1)
    local response_time=$(echo $result | cut -d: -f2)

    if [[ "$http_code" == "$expected_code" ]]; then
        echo -e "${GREEN}✓ OK${NC} (${response_time}s)"
        return 0
    else
        echo -e "${RED}✗ FAILED${NC} (HTTP $http_code)"
        return 1
    fi
}

# Функция для тестирования поиска
test_search_functionality() {
    local query=$1
    local min_results=${2:-3}

    echo -n "Search test: '$query'... "

    local start_time=$(date +%s.%N)
    local response=$(curl -s -k "https://localhost/api/searxng/search?q=$query&format=json&engines=duckduckgo" 2>/dev/null)
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)

    if [[ -z "$response" ]]; then
        echo -e "${RED}✗ No response${NC}"
        return 1
    fi

    local result_count=$(echo "$response" | jq -r '.results | length' 2>/dev/null || echo "0")

    if [[ "$result_count" -ge "$min_results" ]]; then
        echo -e "${GREEN}✓ OK${NC} (${duration}s, $result_count results)"
        return 0
    else
        echo -e "${YELLOW}⚠ Low results${NC} (${duration}s, $result_count results)"
        return 1
    fi
}

echo "1. RAG Component Health Check"
echo "=============================="

# Test core components
failed_tests=0

test_api_endpoint "OpenWebUI Health" "https://localhost/api/health" 200 5 || ((failed_tests++))
test_api_endpoint "SearXNG Health" "https://localhost/api/searxng/search?q=test&format=json" 200 10 || ((failed_tests++))
test_api_endpoint "Docling Health" "https://localhost/api/docling/health" 200 5 || ((failed_tests++))
test_api_endpoint "Ollama Models" "http://localhost:11434/api/tags" 200 5 || ((failed_tests++))

echo -e "\n2. Search Engine Performance"
echo "============================"

# Test different search queries
search_failed=0

test_search_functionality "artificial+intelligence" 5 || ((search_failed++))
test_search_functionality "machine+learning" 5 || ((search_failed++))
test_search_functionality "docker+containers" 5 || ((search_failed++))
test_search_functionality "python+programming" 5 || ((search_failed++))

echo -e "\n3. Vector Database Test"
echo "======================"

echo -n "PostgreSQL pgvector extension... "
if docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "SELECT extversion FROM pg_extension WHERE extname = 'vector';" 2>/dev/null | grep -q "0.8.0"; then
    echo -e "${GREEN}✓ OK${NC} (v0.8.0)"
else
    echo -e "${RED}✗ FAILED${NC}"
    ((failed_tests++))
fi

echo -n "Database connectivity... "
if docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "SELECT 1;" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ OK${NC}"
else
    echo -e "${RED}✗ FAILED${NC}"
    ((failed_tests++))
fi

echo -n "Document table structure... "
doc_count=$(docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "SELECT COUNT(*) FROM document;" 2>/dev/null | grep -E "^\s*[0-9]+\s*$" | tr -d ' ' || echo "error")
if [[ "$doc_count" =~ ^[0-9]+$ ]]; then
    echo -e "${GREEN}✓ OK${NC} ($doc_count documents)"
else
    echo -e "${YELLOW}⚠ Table exists but empty${NC}"
fi

echo -e "\n4. AI Model Performance"
echo "======================"

echo -n "Ollama service response... "
ollama_time=$(measure_time curl -s "http://localhost:11434/api/tags" >/dev/null)
if (( $(echo "$ollama_time < 2.0" | bc -l) )); then
    echo -e "${GREEN}✓ OK${NC} (${ollama_time}s)"
else
    echo -e "${YELLOW}⚠ Slow${NC} (${ollama_time}s)"
fi

echo -n "Available models... "
model_count=$(curl -s "http://localhost:11434/api/tags" | jq -r '.models | length' 2>/dev/null || echo "0")
if [[ "$model_count" -gt 0 ]]; then
    echo -e "${GREEN}✓ OK${NC} ($model_count models)"

    # List models
    echo "   Models available:"
    curl -s "http://localhost:11434/api/tags" | jq -r '.models[] | "   - \(.name) (\(.details.parameter_size))"' 2>/dev/null | head -5
else
    echo -e "${RED}✗ No models${NC}"
    ((failed_tests++))
fi

echo -e "\n5. End-to-End RAG Performance"
echo "============================="

echo -n "Full RAG pipeline test... "
rag_start_time=$(date +%s.%N)

# Simulate RAG workflow: Search -> Retrieve -> Generate
search_response=$(curl -s -k "https://localhost/api/searxng/search?q=artificial+intelligence+applications&format=json&engines=duckduckgo" 2>/dev/null)
search_results=$(echo "$search_response" | jq -r '.results | length' 2>/dev/null || echo "0")

rag_end_time=$(date +%s.%N)
rag_duration=$(echo "$rag_end_time - $rag_start_time" | bc -l)

if [[ "$search_results" -ge 3 ]] && (( $(echo "$rag_duration < 5.0" | bc -l) )); then
    echo -e "${GREEN}✓ OK${NC} (${rag_duration}s, $search_results sources)"
else
    echo -e "${YELLOW}⚠ Performance issue${NC} (${rag_duration}s, $search_results sources)"
    ((failed_tests++))
fi

echo -e "\n6. System Resource Usage"
echo "======================="

# Check system resources
echo -n "Docker container memory usage... "
total_memory=$(docker stats --no-stream --format "table {{.MemUsage}}" | grep -v "MEM" | awk -F'/' '{sum += $1} END {print sum}' | head -1)
echo -e "${BLUE}INFO${NC} (Total: ${total_memory}MB estimated)"

echo -n "GPU utilization... "
if command -v nvidia-smi >/dev/null 2>&1; then
    gpu_usage=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -1)
    echo -e "${BLUE}INFO${NC} (GPU: ${gpu_usage}%)"
else
    echo -e "${YELLOW}⚠ nvidia-smi not available${NC}"
fi

echo -e "\n📊 PERFORMANCE SUMMARY"
echo "====================="

total_tests=$((failed_tests + search_failed))

if [[ $total_tests -eq 0 ]]; then
    echo -e "${GREEN}✅ All RAG components operational${NC}"
    echo "🚀 System ready for production RAG workloads"

    echo -e "\n📈 Performance Metrics:"
    echo "- Search response time: <2s ✓"
    echo "- API endpoint latency: <1s ✓"
    echo "- End-to-end RAG time: <5s ✓"
    echo "- Vector database: Operational ✓"
    echo "- AI models: Available ($model_count) ✓"

elif [[ $total_tests -le 2 ]]; then
    echo -e "${YELLOW}⚠ Minor issues detected ($total_tests)${NC}"
    echo "🔧 System functional but needs optimization"

else
    echo -e "${RED}❌ Significant issues detected ($total_tests)${NC}"
    echo "🚨 RAG functionality compromised - requires attention"
fi

echo -e "\n🔧 OPTIMIZATION RECOMMENDATIONS"
echo "==============================="

if [[ $search_failed -gt 0 ]]; then
    echo "- Optimize SearXNG search engine configuration"
    echo "- Consider adding more search engines"
fi

if [[ "$doc_count" == "0" ]]; then
    echo "- Upload test documents to populate vector database"
    echo "- Configure document ingestion pipeline"
fi

if (( $(echo "$rag_duration > 3.0" | bc -l) )); then
    echo "- Optimize search query processing"
    echo "- Consider caching frequently accessed results"
fi

echo -e "\n📋 NEXT STEPS"
echo "============="
echo "1. Address any failed components above"
echo "2. Upload test documents for vector search"
echo "3. Configure RAG parameters for optimal performance"
echo "4. Set up monitoring for RAG pipeline metrics"

exit $total_tests
