#!/bin/bash

# SearXNG Performance Monitor Script
# Performance monitoring for search engines in ERNI-KI
# Author: Alteon Schultz (Tech Lead)

set -euo pipefail

# Configuration
SEARXNG_URL="http://localhost:8080/api/searxng/search"
LOG_FILE="logs/searxng-performance.log"
SLOW_THRESHOLD=3  # Slow request threshold in seconds
ALERT_THRESHOLD=5 # Alert threshold in seconds

# Create logs directory
mkdir -p logs

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Performance testing function
test_performance() {
    local query="$1"
    local test_name="$2"

    log "Testing: $test_name (query: '$query')"

    # Measure response time
    local response=$(curl -s -w "%{http_code}|%{time_total}" "$SEARXNG_URL?q=$query&format=json" 2>/dev/null || echo "000|999")

    # Parse results
    local http_code=$(echo "$response" | tail -1 | cut -d'|' -f1)
    local curl_time=$(echo "$response" | tail -1 | cut -d'|' -f2)
    local json_response=$(echo "$response" | head -n -1)

    # Analyze JSON response
    local engines_count=0
    local results_count=0
    local active_engines=""

    if [[ "$http_code" == "200" ]] && [[ -n "$json_response" ]]; then
        local analysis=$(echo "$json_response" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    engines = set()
    for result in data.get('results', []):
        if 'engines' in result:
            engines.update(result['engines'])
        elif 'engine' in result:
            engines.add(result['engine'])

    print(f'{len(engines)}|{len(data.get(\"results\", []))}|{\";\".join(sorted(engines))}')
except:
    print('0|0|error')
" 2>/dev/null || echo "0|0|error")

        engines_count=$(echo "$analysis" | cut -d'|' -f1)
        results_count=$(echo "$analysis" | cut -d'|' -f2)
        active_engines=$(echo "$analysis" | cut -d'|' -f3)
    fi

    # Determine performance status (using awk for float comparison)
    local status="OK"
    local is_slow=$(echo "$curl_time $SLOW_THRESHOLD" | awk '{print ($1 > $2)}')
    local is_critical=$(echo "$curl_time $ALERT_THRESHOLD" | awk '{print ($1 > $2)}')

    if [[ "$is_critical" == "1" ]]; then
        status="CRITICAL"
    elif [[ "$is_slow" == "1" ]]; then
        status="SLOW"
    fi

    if [[ "$http_code" != "200" ]]; then
        status="ERROR"
    fi

    # Log results
    log "  Status: $status | HTTP: $http_code | Time: ${curl_time}s"
    log "  Engines: $engines_count active ($active_engines)"
    log "  Results: $results_count"

    # Alert for slow requests
    if [[ "$is_slow" == "1" ]]; then
        log "  SLOW REQUEST: $test_name took ${curl_time}s (>${SLOW_THRESHOLD}s)"
    fi

    echo "$curl_time"
}

# Main monitoring function
main() {
    log "Starting SearXNG performance monitoring"
    log "======================================="

    # Test queries set
    declare -A test_queries=(
        ["basic_search"]="test"
        ["tech_news"]="artificial intelligence news"
        ["documentation"]="docker compose production"
    )

    local test_count=0
    local slow_count=0

    # Execute tests
    for test_name in "${!test_queries[@]}"; do
        local query="${test_queries[$test_name]}"
        test_performance "$query" "$test_name"

        test_count=$((test_count + 1))

        # Pause between tests
        sleep 2
    done

    log "FINAL STATISTICS:"
    log "  Total tests: $test_count"
    log "  Slow threshold: ${SLOW_THRESHOLD}s"

    log "Monitoring completed"
    log "======================================="
}

# Запуск при вызове скрипта напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
