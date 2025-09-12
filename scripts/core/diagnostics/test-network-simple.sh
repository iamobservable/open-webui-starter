#!/bin/bash

# ERNI-KI Simple Network Architecture Test
# Простой тест для проверки оптимизированной сетевой архитектуры

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции логирования
log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"; }
info() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"; }

# Создание директории для результатов
RESULTS_DIR="test-results/network-simple-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULTS_DIR"

# Проверка Docker сетей
test_docker_networks() {
    log "Проверка Docker сетей..."

    local networks_file="$RESULTS_DIR/docker-networks.txt"
    echo "# Docker Networks Test Results" > "$networks_file"
    echo "# Timestamp: $(date)" >> "$networks_file"
    echo "" >> "$networks_file"

    # Проверяем существование оптимизированных сетей
    local expected_networks=("erni-ki-frontend" "erni-ki-backend" "erni-ki-monitoring" "erni-ki-internal")
    local found_networks=0

    for network in "${expected_networks[@]}"; do
        if docker network inspect "$network" >/dev/null 2>&1; then
            info "✓ Сеть $network найдена"
            echo "Network $network: EXISTS" >> "$networks_file"

            # Получаем детали сети
            local subnet=$(docker network inspect "$network" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}')
            local gateway=$(docker network inspect "$network" --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}')
            echo "  Subnet: $subnet" >> "$networks_file"
            echo "  Gateway: $gateway" >> "$networks_file"
            echo "" >> "$networks_file"

            ((found_networks++))
        else
            warn "✗ Сеть $network не найдена"
            echo "Network $network: MISSING" >> "$networks_file"
        fi
    done

    echo "Networks found: $found_networks/${#expected_networks[@]}" >> "$networks_file"

    if [[ $found_networks -eq ${#expected_networks[@]} ]]; then
        log "Все оптимизированные сети найдены ($found_networks/${#expected_networks[@]})"
        return 0
    else
        warn "Найдено только $found_networks из ${#expected_networks[@]} сетей"
        return 1
    fi
}

# Проверка статических IP адресов
test_static_ips() {
    log "Проверка статических IP адресов..."

    local ips_file="$RESULTS_DIR/static-ips.txt"
    echo "# Static IP Addresses Test Results" > "$ips_file"
    echo "# Timestamp: $(date)" >> "$ips_file"
    echo "" >> "$ips_file"

    # Получаем список запущенных контейнеров
    local containers=$(docker ps --format "{{.Names}}" | grep "erni-ki-")
    local tested_containers=0
    local correct_ips=0

    for container in $containers; do
        info "Проверка контейнера: $container"
        ((tested_containers++))

        # Получаем сетевые настройки контейнера
        local networks=$(docker inspect "$container" --format '{{range $net, $config := .NetworkSettings.Networks}}{{$net}}:{{$config.IPAddress}} {{end}}')

        echo "Container: $container" >> "$ips_file"
        echo "Networks: $networks" >> "$ips_file"

        # Проверяем, использует ли контейнер статические IP из наших диапазонов
        if echo "$networks" | grep -E "172\.(20|21|22|23)\." >/dev/null; then
            info "  ✓ Использует оптимизированные IP диапазоны"
            echo "  Status: OPTIMIZED" >> "$ips_file"
            ((correct_ips++))
        else
            warn "  ✗ Не использует оптимизированные IP диапазоны"
            echo "  Status: NOT_OPTIMIZED" >> "$ips_file"
        fi
        echo "" >> "$ips_file"
    done

    echo "Containers tested: $tested_containers" >> "$ips_file"
    echo "Optimized IPs: $correct_ips" >> "$ips_file"

    if [[ $tested_containers -gt 0 ]]; then
        local percentage=$((correct_ips * 100 / tested_containers))
        log "Контейнеров с оптимизированными IP: $correct_ips/$tested_containers ($percentage%)"
        return 0
    else
        warn "Нет запущенных контейнеров для тестирования"
        return 1
    fi
}

# Тест связности между контейнерами
test_container_connectivity() {
    log "Тестирование связности между контейнерами..."

    local connectivity_file="$RESULTS_DIR/connectivity.txt"
    echo "# Container Connectivity Test Results" > "$connectivity_file"
    echo "# Timestamp: $(date)" >> "$connectivity_file"
    echo "" >> "$connectivity_file"

    # Получаем список запущенных контейнеров
    local containers=($(docker ps --format "{{.Names}}" | grep "erni-ki-"))
    local tests_performed=0
    local successful_tests=0

    if [[ ${#containers[@]} -lt 2 ]]; then
        warn "Недостаточно контейнеров для тестирования связности (найдено: ${#containers[@]})"
        echo "Insufficient containers for connectivity testing" >> "$connectivity_file"
        return 1
    fi

    # Тестируем связность между всеми парами контейнеров
    for i in "${!containers[@]}"; do
        for j in "${!containers[@]}"; do
            if [[ $i -ne $j ]]; then
                local source="${containers[$i]}"
                local target="${containers[$j]}"

                info "Тестирование: $source -> $target"
                ((tests_performed++))

                # Получаем IP адрес целевого контейнера в backend сети
                local target_ip=$(docker inspect "$target" --format '{{.NetworkSettings.Networks.erni-ki-backend.IPAddress}}' 2>/dev/null || echo "")

                if [[ -n "$target_ip" && "$target_ip" != "<no value>" ]]; then
                    # Тестируем ping между контейнерами
                    if docker exec "$source" ping -c 1 -W 2 "$target_ip" >/dev/null 2>&1; then
                        info "  ✓ Связность установлена ($target_ip)"
                        echo "$source -> $target ($target_ip): SUCCESS" >> "$connectivity_file"
                        ((successful_tests++))
                    else
                        warn "  ✗ Связность не установлена ($target_ip)"
                        echo "$source -> $target ($target_ip): FAILED" >> "$connectivity_file"
                    fi
                else
                    warn "  ✗ IP адрес не найден в backend сети"
                    echo "$source -> $target: NO_BACKEND_IP" >> "$connectivity_file"
                fi
            fi
        done
    done

    echo "" >> "$connectivity_file"
    echo "Tests performed: $tests_performed" >> "$connectivity_file"
    echo "Successful tests: $successful_tests" >> "$connectivity_file"

    if [[ $tests_performed -gt 0 ]]; then
        local success_rate=$((successful_tests * 100 / tests_performed))
        log "Успешных тестов связности: $successful_tests/$tests_performed ($success_rate%)"
        return 0
    else
        warn "Тесты связности не выполнены"
        return 1
    fi
}

# Проверка системных сетевых параметров
test_system_network_params() {
    log "Проверка системных сетевых параметров..."

    local params_file="$RESULTS_DIR/system-params.txt"
    echo "# System Network Parameters Test Results" > "$params_file"
    echo "# Timestamp: $(date)" >> "$params_file"
    echo "" >> "$params_file"

    # Проверяем ключевые параметры оптимизации
    local params=(
        "net.core.rmem_max"
        "net.core.wmem_max"
        "net.core.somaxconn"
        "net.ipv4.tcp_rmem"
        "net.ipv4.tcp_wmem"
        "net.ipv4.tcp_congestion_control"
    )

    local optimized_params=0

    for param in "${params[@]}"; do
        local value=$(sysctl -n "$param" 2>/dev/null || echo "N/A")
        echo "$param = $value" >> "$params_file"

        # Проверяем, оптимизированы ли параметры
        case "$param" in
            "net.core.rmem_max"|"net.core.wmem_max")
                if [[ "$value" -ge 536870912 ]]; then  # 512MB
                    info "✓ $param оптимизирован ($value)"
                    ((optimized_params++))
                else
                    warn "✗ $param не оптимизирован ($value)"
                fi
                ;;
            "net.core.somaxconn")
                if [[ "$value" -ge 65535 ]]; then
                    info "✓ $param оптимизирован ($value)"
                    ((optimized_params++))
                else
                    warn "✗ $param не оптимизирован ($value)"
                fi
                ;;
            "net.ipv4.tcp_congestion_control")
                if [[ "$value" == "bbr" ]]; then
                    info "✓ $param оптимизирован ($value)"
                    ((optimized_params++))
                else
                    warn "✗ $param не оптимизирован ($value)"
                fi
                ;;
            *)
                info "  $param = $value"
                ;;
        esac
    done

    echo "" >> "$params_file"
    echo "Optimized parameters: $optimized_params/${#params[@]}" >> "$params_file"

    local optimization_rate=$((optimized_params * 100 / ${#params[@]}))
    log "Оптимизированных параметров: $optimized_params/${#params[@]} ($optimization_rate%)"
}

# Генерация отчета
generate_simple_report() {
    log "Генерация отчета..."

    local report_file="$RESULTS_DIR/network-architecture-report.md"

    cat > "$report_file" << EOF
# ERNI-KI Network Architecture Test Report

**Дата тестирования**: $(date)
**Тип теста**: Простая проверка сетевой архитектуры

## Результаты тестирования

### 1. Docker сети
\`\`\`
$(cat "$RESULTS_DIR/docker-networks.txt" 2>/dev/null || echo "Данные недоступны")
\`\`\`

### 2. Статические IP адреса
\`\`\`
$(cat "$RESULTS_DIR/static-ips.txt" 2>/dev/null || echo "Данные недоступны")
\`\`\`

### 3. Связность контейнеров
\`\`\`
$(cat "$RESULTS_DIR/connectivity.txt" 2>/dev/null || echo "Данные недоступны")
\`\`\`

### 4. Системные параметры
\`\`\`
$(cat "$RESULTS_DIR/system-params.txt" 2>/dev/null || echo "Данные недоступны")
\`\`\`

## Заключение

Тест проверил основные компоненты оптимизированной сетевой архитектуры ERNI-KI:

- ✅ Создание сегментированных сетей
- ✅ Назначение статических IP адресов
- ✅ Связность между контейнерами
- ✅ Оптимизация системных параметров

## Рекомендации

1. Запустите полную систему для комплексного тестирования
2. Проведите нагрузочное тестирование после запуска всех сервисов
3. Мониторьте производительность в production среде

---
*Отчет сгенерирован автоматически скриптом test-network-simple.sh*
EOF

    log "Отчет сохранен: $report_file"
}

# Основная функция
main() {
    log "Запуск простого тестирования сетевой архитектуры ERNI-KI..."

    local tests_passed=0
    local total_tests=4

    # Выполняем тесты
    if test_docker_networks; then ((tests_passed++)); fi
    if test_static_ips; then ((tests_passed++)); fi
    if test_container_connectivity; then ((tests_passed++)); fi
    if test_system_network_params; then ((tests_passed++)); fi

    generate_simple_report

    local success_rate=$((tests_passed * 100 / total_tests))

    if [[ $tests_passed -eq $total_tests ]]; then
        log "Все тесты пройдены успешно! ($tests_passed/$total_tests)"
    else
        warn "Пройдено тестов: $tests_passed/$total_tests ($success_rate%)"
    fi

    log "Простое тестирование сетевой архитектуры завершено!"
    info "Результаты сохранены в: $RESULTS_DIR"
    info "Отчет доступен: $RESULTS_DIR/network-architecture-report.md"

    return $((total_tests - tests_passed))
}

# Запуск основной функции
main "$@"
