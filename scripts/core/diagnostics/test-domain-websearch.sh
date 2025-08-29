#!/bin/bash

# Domain Web Search Testing Script for ERNI-KI
# Скрипт тестирования веб-поиска через разные домены

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции для логирования
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

# Функция тестирования веб-поиска
test_websearch() {
    local domain=$1
    local protocol=$2
    local url="${protocol}://${domain}"
    
    log "Тестирование веб-поиска через ${url}..."
    
    # Тест API endpoint
    local api_url="${url}/api/searxng/search"
    local search_data="q=test&category_general=1&format=json"
    
    echo "  🔍 Тестирование API endpoint: ${api_url}"
    
    # Выполняем запрос с таймаутом
    local response
    local http_code
    local result_count
    
    if response=$(curl -k -s -w "%{http_code}" -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "$search_data" \
        --max-time 15 \
        "$api_url" 2>/dev/null); then
        
        # Извлекаем HTTP код (последние 3 символа)
        http_code="${response: -3}"
        # Извлекаем JSON (все кроме последних 3 символов)
        json_response="${response%???}"
        
        echo "    HTTP код: $http_code"
        
        if [ "$http_code" = "200" ]; then
            # Проверяем, что ответ - валидный JSON
            if echo "$json_response" | jq . >/dev/null 2>&1; then
                result_count=$(echo "$json_response" | jq '.results | length' 2>/dev/null || echo "0")
                if [ "$result_count" -gt 0 ]; then
                    success "    ✅ API работает: $result_count результатов"
                    return 0
                else
                    warning "    ⚠️  API вернул пустые результаты"
                    return 1
                fi
            else
                error "    ❌ Ответ не является валидным JSON"
                echo "    Первые 200 символов ответа: ${json_response:0:200}"
                return 1
            fi
        else
            error "    ❌ HTTP ошибка: $http_code"
            echo "    Ответ: ${json_response:0:200}"
            return 1
        fi
    else
        error "    ❌ Не удалось выполнить запрос (таймаут или сетевая ошибка)"
        return 1
    fi
}

# Функция тестирования основного интерфейса
test_main_interface() {
    local domain=$1
    local protocol=$2
    local url="${protocol}://${domain}"
    
    echo "  🌐 Тестирование основного интерфейса: ${url}/"
    
    local response
    local http_code
    
    if response=$(curl -k -s -w "%{http_code}" --max-time 10 "$url/" 2>/dev/null); then
        http_code="${response: -3}"
        
        if [ "$http_code" = "200" ]; then
            success "    ✅ Основной интерфейс доступен"
            return 0
        else
            warning "    ⚠️  HTTP код: $http_code"
            return 1
        fi
    else
        error "    ❌ Основной интерфейс недоступен"
        return 1
    fi
}

# Функция тестирования health check
test_health() {
    local domain=$1
    local protocol=$2
    local url="${protocol}://${domain}"
    
    echo "  💚 Тестирование health check: ${url}/health"
    
    local response
    local http_code
    
    if response=$(curl -k -s -w "%{http_code}" --max-time 5 "$url/health" 2>/dev/null); then
        http_code="${response: -3}"
        
        if [ "$http_code" = "200" ]; then
            success "    ✅ Health check работает"
            return 0
        else
            warning "    ⚠️  Health check HTTP код: $http_code"
            return 1
        fi
    else
        error "    ❌ Health check недоступен"
        return 1
    fi
}

# Основная функция тестирования домена
test_domain() {
    local domain=$1
    local protocol=$2
    
    echo ""
    echo "=================================================="
    echo "🧪 ТЕСТИРОВАНИЕ ДОМЕНА: ${protocol}://${domain}"
    echo "=================================================="
    
    local tests_passed=0
    local total_tests=3
    
    # Тест 1: Health check
    if test_health "$domain" "$protocol"; then
        ((tests_passed++))
    fi
    
    # Тест 2: Основной интерфейс
    if test_main_interface "$domain" "$protocol"; then
        ((tests_passed++))
    fi
    
    # Тест 3: Веб-поиск API
    if test_websearch "$domain" "$protocol"; then
        ((tests_passed++))
    fi
    
    echo ""
    echo "📊 Результат для ${domain}: $tests_passed/$total_tests тестов пройдено"
    
    if [ $tests_passed -eq $total_tests ]; then
        success "🎉 Все тесты пройдены для ${domain}!"
        return 0
    else
        warning "⚠️  Некоторые тесты не пройдены для ${domain}"
        return 1
    fi
}

# Генерация отчета
generate_report() {
    local results=("$@")
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo ""
    echo "=================================================="
    echo "📋 ИТОГОВЫЙ ОТЧЕТ ТЕСТИРОВАНИЯ"
    echo "=================================================="
    echo "Время: $timestamp"
    echo ""
    
    local total_domains=0
    local passed_domains=0
    
    for result in "${results[@]}"; do
        domain=$(echo "$result" | cut -d: -f1)
        status=$(echo "$result" | cut -d: -f2)
        
        ((total_domains++))
        
        if [ "$status" = "PASS" ]; then
            success "✅ $domain - ВСЕ ТЕСТЫ ПРОЙДЕНЫ"
            ((passed_domains++))
        else
            error "❌ $domain - ЕСТЬ ПРОБЛЕМЫ"
        fi
    done
    
    echo ""
    echo "📈 ОБЩАЯ СТАТИСТИКА:"
    echo "   Всего доменов протестировано: $total_domains"
    echo "   Успешно прошли все тесты: $passed_domains"
    echo "   Процент успеха: $((passed_domains * 100 / total_domains))%"
    
    if [ $passed_domains -eq $total_domains ]; then
        echo ""
        success "🎉 ВСЕ ДОМЕНЫ РАБОТАЮТ КОРРЕКТНО!"
        echo "   Проблема с веб-поиском через diz.zone РЕШЕНА!"
    else
        echo ""
        warning "⚠️  ОБНАРУЖЕНЫ ПРОБЛЕМЫ С НЕКОТОРЫМИ ДОМЕНАМИ"
        echo "   Требуется дополнительная диагностика"
    fi
}

# Основная функция
main() {
    log "Запуск комплексного тестирования веб-поиска через разные домены..."
    
    # Проверка доступности jq
    if ! command -v jq >/dev/null 2>&1; then
        error "jq не установлен. Установите: sudo apt-get install jq"
        exit 1
    fi
    
    # Массив для результатов
    local results=()
    
    # Тестируем localhost (HTTP и HTTPS)
    if test_domain "localhost" "http"; then
        results+=("localhost:PASS")
    else
        results+=("localhost:FAIL")
    fi
    
    if test_domain "localhost" "https"; then
        results+=("localhost-https:PASS")
    else
        results+=("localhost-https:FAIL")
    fi
    
    # Примечание: diz.zone и webui.diz.zone требуют настройки DNS/hosts
    # Для полного тестирования нужно добавить в /etc/hosts:
    # 127.0.0.1 diz.zone webui.diz.zone
    
    echo ""
    warning "ПРИМЕЧАНИЕ: Для тестирования diz.zone и webui.diz.zone"
    warning "добавьте в /etc/hosts: 127.0.0.1 diz.zone webui.diz.zone"
    
    # Генерируем отчет
    generate_report "${results[@]}"
    
    # Сохраняем отчет в файл
    local report_file="domain_websearch_test_$(date +%Y%m%d_%H%M%S).txt"
    {
        echo "Domain Web Search Test Report"
        echo "Generated: $(date)"
        echo "=============================="
        echo ""
        for result in "${results[@]}"; do
            echo "$result"
        done
    } > "$report_file"
    
    log "Отчет сохранен в: $report_file"
}

# Запуск скрипта
main "$@"
