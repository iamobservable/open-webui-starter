#!/bin/bash

# SearXNG Healthcheck Fix Script for ERNI-KI
# Скрипт исправления healthcheck для SearXNG

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
    exit 1
}

# Диагностика текущего состояния
diagnose_current_state() {
    log "Диагностика текущего состояния SearXNG healthcheck..."

    echo "=== Статус контейнера ==="
    docker-compose ps searxng
    echo ""

    echo "=== Текущая конфигурация healthcheck ==="
    grep -A 6 "healthcheck:" compose.yml | grep -A 6 searxng || echo "Healthcheck не найден"
    echo ""

    echo "=== Проверка доступности endpoints ==="

    # Внешняя проверка
    if curl -f -s http://localhost:8081/ >/dev/null; then
        success "Внешний доступ к SearXNG: OK"
    else
        warning "Внешний доступ к SearXNG: FAILED"
    fi

    # Проверка healthz endpoint
    if curl -f -s http://localhost:8081/healthz >/dev/null; then
        success "Healthz endpoint: OK"
    else
        warning "Healthz endpoint: FAILED"
    fi

    # Внутренняя проверка с curl
    if docker-compose exec -T searxng curl --fail http://localhost:8080/ >/dev/null 2>&1; then
        success "Внутренний curl: OK"
    else
        warning "Внутренний curl: FAILED (curl может отсутствовать)"
    fi

    # Внутренняя проверка с wget
    if docker-compose exec -T searxng wget -q --spider http://localhost:8080/ 2>/dev/null; then
        success "Внутренний wget: OK"
    else
        warning "Внутренний wget: FAILED"
    fi

    # Проверка Python
    if docker-compose exec -T searxng python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/')" 2>/dev/null; then
        success "Внутренний Python: OK"
    else
        warning "Внутренний Python: FAILED"
    fi

    echo ""
}

# Создание резервной копии
backup_compose() {
    log "Создание резервной копии compose.yml..."

    local backup_file="compose.yml.backup.$(date +%Y%m%d_%H%M%S)"
    cp compose.yml "$backup_file"

    success "Резервная копия создана: $backup_file"
}

# Исправление healthcheck конфигурации
fix_healthcheck_config() {
    log "Исправление конфигурации healthcheck..."

    # Создаем временный файл с новой конфигурацией healthcheck
    cat > /tmp/new_healthcheck.yml << 'EOF'
    healthcheck:
      test:
        - "CMD-SHELL"
        - |
          # Попробуем несколько методов проверки
          wget -q --spider http://localhost:8080/ || \
          python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/')" || \
          nc -z localhost 8080 || \
          exit 1
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
EOF

    # Обновляем compose.yml
    # Находим строку с healthcheck и заменяем весь блок
    python3 << 'PYTHON_SCRIPT'
import re
import sys

# Читаем файл
with open('compose.yml', 'r') as f:
    content = f.read()

# Новая конфигурация healthcheck
new_healthcheck = '''    healthcheck:
      test:
        - "CMD-SHELL"
        - |
          # Попробуем несколько методов проверки
          wget -q --spider http://localhost:8080/ || \\
          python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/')" || \\
          nc -z localhost 8080 || \\
          exit 1
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s'''

# Паттерн для поиска существующего healthcheck блока SearXNG
pattern = r'(  searxng:.*?\n)(    healthcheck:.*?\n(?:      .*?\n)*)(.*?)(?=\n  \w|\nvolumes:|\nnetworks:|\Z)'

def replace_healthcheck(match):
    before = match.group(1)
    after = match.group(3) if match.group(3) else ''
    return before + new_healthcheck + '\n' + after

# Заменяем healthcheck
new_content = re.sub(pattern, replace_healthcheck, content, flags=re.DOTALL)

# Записываем обновленный файл
with open('compose.yml', 'w') as f:
    f.write(new_content)

print("Healthcheck конфигурация обновлена")
PYTHON_SCRIPT

    success "Конфигурация healthcheck обновлена"
}

# Проверка конфигурации
validate_config() {
    log "Проверка конфигурации Docker Compose..."

    if docker-compose config >/dev/null 2>&1; then
        success "Docker Compose конфигурация валидна"
    else
        error "Ошибка в Docker Compose конфигурации"
    fi
}

# Перезапуск контейнера
restart_searxng() {
    log "Перезапуск контейнера SearXNG..."

    # Останавливаем контейнер
    docker-compose stop searxng

    # Запускаем с новой конфигурацией
    docker-compose up -d searxng

    success "Контейнер SearXNG перезапущен"
}

# Ожидание готовности сервиса
wait_for_service() {
    log "Ожидание готовности SearXNG..."

    local max_attempts=60  # 2 минуты
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -f -s http://localhost:8081/ >/dev/null 2>&1; then
            success "SearXNG готов к работе"
            return 0
        fi

        if [ $((attempt % 10)) -eq 0 ]; then
            log "Попытка $attempt/$max_attempts: ожидание готовности SearXNG..."
        fi

        sleep 2
        ((attempt++))
    done

    error "SearXNG не готов после $max_attempts попыток"
}

# Проверка healthcheck
test_healthcheck() {
    log "Тестирование нового healthcheck..."

    # Ждем несколько циклов healthcheck
    sleep 35

    local status
    status=$(docker-compose ps searxng --format "table {{.Name}}\t{{.Status}}")

    echo "=== Статус после исправления ==="
    echo "$status"
    echo ""

    if echo "$status" | grep -q "healthy"; then
        success "Healthcheck работает корректно!"
        return 0
    elif echo "$status" | grep -q "unhealthy"; then
        warning "Healthcheck все еще не проходит"
        return 1
    else
        warning "Статус healthcheck неопределен"
        return 1
    fi
}

# Дополнительная диагностика при неудаче
additional_diagnostics() {
    log "Дополнительная диагностика..."

    echo "=== Логи SearXNG (последние 20 строк) ==="
    docker-compose logs --tail=20 searxng
    echo ""

    echo "=== Тестирование healthcheck команды вручную ==="
    docker-compose exec -T searxng sh -c '
        echo "Тест wget:"
        wget -q --spider http://localhost:8080/ && echo "OK" || echo "FAILED"

        echo "Тест Python:"
        python3 -c "import urllib.request; urllib.request.urlopen(\"http://localhost:8080/\")" && echo "OK" || echo "FAILED"

        echo "Тест netcat:"
        nc -z localhost 8080 && echo "OK" || echo "FAILED"

        echo "Проверка процессов:"
        ps aux | grep -E "(uwsgi|searx)" | head -5
    '
    echo ""
}

# Генерация отчета
generate_report() {
    log "Генерация отчета..."

    local report_file="searxng_healthcheck_fix_$(date +%Y%m%d_%H%M%S).txt"

    {
        echo "SearXNG Healthcheck Fix Report"
        echo "Generated: $(date)"
        echo "=============================="
        echo ""

        echo "PROBLEM:"
        echo "- SearXNG container status: unhealthy"
        echo "- Healthcheck using curl which is not available in container"
        echo ""

        echo "SOLUTION:"
        echo "- Updated healthcheck to use wget, python3, and netcat as fallbacks"
        echo "- Increased timeout from 3s to 10s"
        echo "- Increased start_period from 15s to 30s"
        echo "- Reduced retries from 5 to 3"
        echo ""

        echo "CURRENT STATUS:"
        docker-compose ps searxng
        echo ""

        echo "HEALTHCHECK CONFIGURATION:"
        grep -A 10 "healthcheck:" compose.yml | grep -A 10 -B 2 "wget"
        echo ""

        echo "RECENT LOGS:"
        docker-compose logs --tail=10 searxng

    } > "$report_file"

    success "Отчет сохранен в: $report_file"
}

# Основная функция
main() {
    log "Запуск исправления SearXNG healthcheck..."

    # Проверка, что мы в корне проекта
    if [ ! -f "compose.yml" ]; then
        error "Файл compose.yml не найден. Запустите скрипт из корня проекта."
    fi

    diagnose_current_state
    backup_compose
    fix_healthcheck_config
    validate_config
    restart_searxng
    wait_for_service

    if test_healthcheck; then
        success "Healthcheck исправлен успешно!"
    else
        warning "Healthcheck все еще не работает, выполняем дополнительную диагностику..."
        additional_diagnostics
    fi

    generate_report

    echo ""
    log "Исправление завершено. Проверьте статус:"
    echo "- docker-compose ps searxng"
    echo "- docker-compose logs searxng"

    if docker-compose ps searxng | grep -q "healthy"; then
        success "🎉 SearXNG теперь имеет статус 'healthy'!"
    else
        warning "⚠️  SearXNG все еще не имеет статус 'healthy'. Проверьте логи."
    fi
}

# Запуск скрипта
main "$@"
