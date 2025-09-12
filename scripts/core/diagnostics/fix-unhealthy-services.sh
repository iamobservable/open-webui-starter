#!/bin/bash
# Скрипт для исправления проблемных сервисов ERNI-KI
# Автоматическое восстановление unhealthy контейнеров

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции логирования
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

# Проверка статуса сервиса
check_service_health() {
    local service_name="$1"
    local status=$(docker-compose ps "$service_name" --format "table {{.State}}" | tail -n +2)

    if [[ "$status" == *"unhealthy"* ]]; then
        return 1
    elif [[ "$status" == *"healthy"* ]] || [[ "$status" == *"running"* ]]; then
        return 0
    else
        return 2
    fi
}

# Исправление EdgeTTS
fix_edgetts() {
    log "Исправление EdgeTTS..."

    # Проверяем логи
    log "Анализ логов EdgeTTS..."
    docker-compose logs edgetts | tail -20

    # Перезапускаем сервис
    log "Перезапуск EdgeTTS..."
    docker-compose restart edgetts

    # Ждем запуска
    sleep 10

    # Проверяем статус
    if check_service_health "edgetts"; then
        success "EdgeTTS восстановлен"
        return 0
    else
        warning "EdgeTTS все еще нездоров, требует ручного вмешательства"
        return 1
    fi
}

# Исправление SearXNG
fix_searxng() {
    log "Исправление SearXNG..."

    # Проверяем логи
    log "Анализ логов SearXNG..."
    docker-compose logs searxng | tail -20

    # Перезапускаем сервис
    log "Перезапуск SearXNG..."
    docker-compose restart searxng

    # Ждем запуска
    sleep 15

    # Проверяем статус
    if check_service_health "searxng"; then
        success "SearXNG восстановлен"
        return 0
    else
        warning "SearXNG все еще нездоров, возможны проблемы с внешними поисковыми движками"
        return 1
    fi
}

# Исправление Cloudflared
fix_cloudflared() {
    log "Исправление Cloudflared..."

    # Проверяем логи
    log "Анализ логов Cloudflared..."
    docker-compose logs cloudflared | tail -20

    # Проверяем наличие токена
    if [[ ! -f "env/cloudflared.env" ]] || ! grep -q "TUNNEL_TOKEN" env/cloudflared.env; then
        warning "Cloudflared токен не настроен. Пропускаем восстановление."
        return 1
    fi

    # Перезапускаем сервис
    log "Перезапуск Cloudflared..."
    docker-compose restart cloudflared

    # Ждем запуска
    sleep 10

    # Проверяем статус
    if check_service_health "cloudflared"; then
        success "Cloudflared восстановлен"
        return 0
    else
        warning "Cloudflared все еще нездоров, проверьте токен и сетевое подключение"
        return 1
    fi
}

# Исправление Tika
fix_tika() {
    log "Исправление Tika..."

    # Проверяем логи
    log "Анализ логов Tika..."
    docker-compose logs tika | tail -20

    # Перезапускаем сервис
    log "Перезапуск Tika..."
    docker-compose restart tika

    # Ждем запуска (Tika медленно стартует)
    sleep 30

    # Проверяем статус
    if check_service_health "tika"; then
        success "Tika восстановлен"
        return 0
    else
        warning "Tika все еще нездоров, возможно требуется больше времени для запуска"
        return 1
    fi
}

# Общая проверка системы
system_check() {
    log "Проверка состояния всех сервисов..."

    local unhealthy_services=()
    local services=("auth" "db" "redis" "ollama" "nginx" "openwebui" "searxng" "docling" "edgetts" "tika" "mcposerver" "cloudflared" "watchtower")

    for service in "${services[@]}"; do
        if ! check_service_health "$service"; then
            unhealthy_services+=("$service")
        fi
    done

    if [[ ${#unhealthy_services[@]} -eq 0 ]]; then
        success "Все сервисы здоровы!"
        return 0
    else
        warning "Нездоровые сервисы: ${unhealthy_services[*]}"
        return 1
    fi
}

# Основная функция
main() {
    log "Запуск автоматического исправления проблемных сервисов..."
    echo ""

    # Проверяем текущее состояние
    system_check
    echo ""

    local fixed_count=0
    local total_issues=0

    # Исправляем EdgeTTS
    if ! check_service_health "edgetts"; then
        ((total_issues++))
        if fix_edgetts; then
            ((fixed_count++))
        fi
        echo ""
    fi

    # Исправляем SearXNG
    if ! check_service_health "searxng"; then
        ((total_issues++))
        if fix_searxng; then
            ((fixed_count++))
        fi
        echo ""
    fi

    # Исправляем Cloudflared
    if ! check_service_health "cloudflared"; then
        ((total_issues++))
        if fix_cloudflared; then
            ((fixed_count++))
        fi
        echo ""
    fi

    # Исправляем Tika
    if ! check_service_health "tika"; then
        ((total_issues++))
        if fix_tika; then
            ((fixed_count++))
        fi
        echo ""
    fi

    # Финальная проверка
    log "Финальная проверка системы..."
    system_check

    # Результаты
    echo ""
    log "Результаты восстановления:"
    echo "- Исправлено сервисов: $fixed_count из $total_issues"
    echo "- Статус системы: $(docker-compose ps --format 'table {{.Service}}\t{{.State}}' | grep -c healthy || echo 0) здоровых сервисов"

    if [[ $fixed_count -eq $total_issues ]] && [[ $total_issues -gt 0 ]]; then
        success "Все проблемы исправлены!"
    elif [[ $fixed_count -gt 0 ]]; then
        warning "Частично исправлено. Некоторые сервисы требуют ручного вмешательства."
    elif [[ $total_issues -eq 0 ]]; then
        success "Проблем не обнаружено!"
    else
        error "Не удалось исправить проблемы автоматически."
    fi

    echo ""
    log "Рекомендации:"
    echo "1. Проверьте логи проблемных сервисов: docker-compose logs <service>"
    echo "2. Для полной диагностики: ./scripts/health_check.sh"
    echo "3. Мониторинг системы: docker-compose ps"
}

# Запуск скрипта
main "$@"
