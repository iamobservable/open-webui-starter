#!/bin/bash

# ERNI-KI Security Fixes Application Script
# Скрипт для применения исправлений безопасности nginx без полной перезагрузки системы

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция логирования
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
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

# Проверка прав доступа
if [[ $EUID -eq 0 ]]; then
   error "Этот скрипт не должен запускаться от root"
   exit 1
fi

# Проверка наличия docker-compose
if ! command -v docker-compose &> /dev/null; then
    error "docker-compose не найден"
    exit 1
fi

log "🔧 Начинаем применение исправлений безопасности ERNI-KI..."

# Создание резервной копии текущей конфигурации
BACKUP_DIR=".config-backup/nginx-security-$(date +%Y%m%d-%H%M%S)"
log "📦 Создание резервной копии в $BACKUP_DIR..."
mkdir -p "$BACKUP_DIR"
cp -r conf/nginx/ "$BACKUP_DIR/"
success "Резервная копия создана"

# Проверка синтаксиса nginx конфигурации
log "🔍 Проверка синтаксиса nginx конфигурации..."
if docker-compose exec -T nginx nginx -t; then
    success "Синтаксис конфигурации корректен"
else
    error "Ошибка в синтаксисе nginx конфигурации"
    log "Восстанавливаем из резервной копии..."
    cp -r "$BACKUP_DIR/nginx/" conf/
    exit 1
fi

# Применение изменений с graceful reload
log "🔄 Применение изменений nginx (graceful reload)..."
if docker-compose exec -T nginx nginx -s reload; then
    success "Конфигурация nginx успешно перезагружена"
else
    error "Ошибка при перезагрузке nginx"
    log "Восстанавливаем из резервной копии..."
    cp -r "$BACKUP_DIR/nginx/" conf/
    docker-compose exec -T nginx nginx -s reload
    exit 1
fi

# Проверка статуса всех сервисов
log "🏥 Проверка статуса всех сервисов..."
UNHEALTHY_SERVICES=$(docker-compose ps --format "table {{.Service}}\t{{.Status}}" | grep -v "Up.*healthy" | grep -v "SERVICE" | wc -l)

if [ "$UNHEALTHY_SERVICES" -gt 0 ]; then
    warning "Обнаружены нездоровые сервисы:"
    docker-compose ps --format "table {{.Service}}\t{{.Status}}" | grep -v "Up.*healthy" | grep -v "SERVICE"
else
    success "Все сервисы работают корректно"
fi

# Тестирование HTTPS доступа
log "🔐 Тестирование HTTPS доступа..."
if curl -s -I -k https://localhost >/dev/null 2>&1; then
    success "HTTPS доступ работает"
else
    warning "Проблемы с HTTPS доступом"
fi

# Проверка заголовков безопасности
log "🛡️ Проверка заголовков безопасности..."
SECURITY_HEADERS=$(curl -s -I -k https://localhost | grep -E "(strict-transport-security|content-security-policy|x-frame-options)" | wc -l)
if [ "$SECURITY_HEADERS" -ge 3 ]; then
    success "Заголовки безопасности настроены корректно"
else
    warning "Некоторые заголовки безопасности отсутствуют"
fi

# Проверка rate limiting
log "⚡ Проверка rate limiting..."
if docker-compose exec -T nginx test -f /var/log/nginx/rate_limit.log; then
    success "Rate limiting логирование настроено"
else
    warning "Rate limiting логирование не настроено"
fi

# Финальная проверка
log "✅ Финальная проверка системы..."
TOTAL_SERVICES=$(docker-compose ps --format "table {{.Service}}" | grep -v "SERVICE" | wc -l)
HEALTHY_SERVICES=$(docker-compose ps --format "table {{.Service}}\t{{.Status}}" | grep "Up.*healthy" | wc -l)

echo
echo "📊 Статистика системы:"
echo "   Всего сервисов: $TOTAL_SERVICES"
echo "   Здоровых сервисов: $HEALTHY_SERVICES"
echo "   Резервная копия: $BACKUP_DIR"
echo

if [ "$HEALTHY_SERVICES" -eq "$TOTAL_SERVICES" ]; then
    success "🎉 Исправления безопасности успешно применены!"
    success "Все $TOTAL_SERVICES сервисов работают корректно"
else
    warning "⚠️ Исправления применены, но есть проблемы с некоторыми сервисами"
    echo "Проверьте логи проблемных сервисов: docker-compose logs [service_name]"
fi

log "🔍 Для мониторинга безопасности используйте:"
echo "   - Логи rate limiting: docker-compose exec nginx tail -f /var/log/nginx/rate_limit.log"
echo "   - Статус nginx: curl -s http://localhost:8080/nginx_status"
echo "   - Проверка заголовков: curl -I -k https://localhost"

echo
success "Применение исправлений безопасности завершено!"
