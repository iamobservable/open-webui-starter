#!/bin/bash

# ERNI-KI Models Page Testing Script
# Скрипт для тестирования страницы моделей OpenWebUI

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Конфигурация
DOMAIN="ki.erni-gruppe.ch"
MODELS_PAGE="https://$DOMAIN/workspace/models"
TIMEOUT=10

# Функции логирования
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

log "🔍 Начинаем тестирование страницы моделей OpenWebUI..."

# 1. Проверка доступности страницы моделей
log "1. Проверка HTTP статуса страницы /workspace/models..."
STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout $TIMEOUT "$MODELS_PAGE" 2>/dev/null || echo "000")

if [ "$STATUS_CODE" = "200" ]; then
    success "Страница моделей доступна: HTTP $STATUS_CODE"
else
    error "Страница моделей недоступна: HTTP $STATUS_CODE"
    exit 1
fi

# 2. Проверка времени отклика
log "2. Измерение времени отклика страницы..."
RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" --connect-timeout $TIMEOUT "$MODELS_PAGE" 2>/dev/null || echo "999")

if (( $(echo "$RESPONSE_TIME < 3.0" | bc -l) )); then
    success "Время отклика: ${RESPONSE_TIME}s (цель <3s)"
else
    warning "Время отклика: ${RESPONSE_TIME}s (превышает цель 3s)"
fi

# 3. Проверка содержимого страницы
log "3. Проверка содержимого HTML страницы..."
PAGE_CONTENT=$(curl -s --connect-timeout $TIMEOUT "$MODELS_PAGE" 2>/dev/null || echo "")

if echo "$PAGE_CONTENT" | grep -q "Open WebUI"; then
    success "HTML содержимое корректно (найден заголовок Open WebUI)"
else
    warning "HTML содержимое может быть некорректным"
fi

# 4. Проверка API endpoints для моделей
log "4. Проверка API endpoints..."

# 4a. Проверка /api/models (требует аутентификации)
log "4a. Проверка /api/models (ожидается 401)..."
API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout $TIMEOUT "https://$DOMAIN/api/models" 2>/dev/null || echo "000")

if [ "$API_STATUS" = "401" ]; then
    success "API /api/models корректно требует аутентификацию: HTTP $API_STATUS"
elif [ "$API_STATUS" = "200" ]; then
    warning "API /api/models доступен без аутентификации: HTTP $API_STATUS"
else
    error "API /api/models недоступен: HTTP $API_STATUS"
fi

# 4b. Проверка нового публичного endpoint
log "4b. Проверка /api/models/status (публичный)..."
STATUS_API=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout $TIMEOUT "https://$DOMAIN/api/models/status" 2>/dev/null || echo "000")

if [ "$STATUS_API" = "200" ]; then
    success "Публичный API /api/models/status доступен: HTTP $STATUS_API"
    
    # Проверка содержимого ответа
    STATUS_CONTENT=$(curl -s --connect-timeout $TIMEOUT "https://$DOMAIN/api/models/status" 2>/dev/null || echo "{}")
    if echo "$STATUS_CONTENT" | jq -e '.status' >/dev/null 2>&1; then
        success "JSON ответ корректен: $(echo "$STATUS_CONTENT" | jq -c '.')"
    else
        warning "JSON ответ некорректен: $STATUS_CONTENT"
    fi
else
    error "Публичный API /api/models/status недоступен: HTTP $STATUS_API"
fi

# 5. Проверка backend сервисов
log "5. Проверка backend сервисов..."

# 5a. Ollama
log "5a. Проверка Ollama..."
OLLAMA_MODELS=$(curl -s http://localhost:11434/api/tags 2>/dev/null | jq '.models | length' 2>/dev/null || echo "0")
if [ "$OLLAMA_MODELS" -gt 0 ]; then
    success "Ollama: $OLLAMA_MODELS моделей доступно"
else
    error "Ollama: модели недоступны"
fi

# 5b. OpenWebUI health
log "5b. Проверка OpenWebUI health..."
HEALTH_STATUS=$(curl -s "https://$DOMAIN/api/health" 2>/dev/null | jq -r '.status' 2>/dev/null || echo "false")
if [ "$HEALTH_STATUS" = "true" ]; then
    success "OpenWebUI health: OK"
else
    error "OpenWebUI health: FAILED"
fi

# 6. Проверка статических ресурсов
log "6. Проверка статических ресурсов..."
STATIC_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout $TIMEOUT "https://$DOMAIN/static/favicon.png" 2>/dev/null || echo "000")

if [ "$STATIC_STATUS" = "200" ]; then
    success "Статические ресурсы доступны: HTTP $STATIC_STATUS"
else
    warning "Проблемы со статическими ресурсами: HTTP $STATIC_STATUS"
fi

# 7. Проверка конфигурации аутентификации
log "7. Проверка конфигурации аутентификации..."
AUTH_CONFIG=$(curl -s "https://$DOMAIN/api/config" 2>/dev/null | jq -r '.auth' 2>/dev/null || echo "null")

if [ "$AUTH_CONFIG" = "true" ]; then
    success "Аутентификация включена (безопасность обеспечена)"
else
    warning "Аутентификация отключена (потенциальная проблема безопасности)"
fi

# Итоговый отчет
echo
log "📊 Итоговый отчет тестирования страницы моделей:"
echo "   Страница /workspace/models: HTTP $STATUS_CODE"
echo "   Время отклика: ${RESPONSE_TIME}s"
echo "   API /api/models: HTTP $API_STATUS (требует аутентификацию)"
echo "   API /api/models/status: HTTP $STATUS_API (публичный)"
echo "   Ollama модели: $OLLAMA_MODELS"
echo "   OpenWebUI health: $HEALTH_STATUS"
echo "   Статические ресурсы: HTTP $STATIC_STATUS"
echo "   Аутентификация: $AUTH_CONFIG"

# Определение общего статуса
CRITICAL_ISSUES=0

if [ "$STATUS_CODE" != "200" ]; then
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi

if [ "$HEALTH_STATUS" != "true" ]; then
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi

if [ "$OLLAMA_MODELS" -eq 0 ]; then
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi

echo
if [ "$CRITICAL_ISSUES" -eq 0 ]; then
    success "🎉 Все критические проверки пройдены! Страница моделей функционирует корректно."
    echo
    echo "📝 Примечания:"
    echo "   - Страница загружается корректно (HTTP 200)"
    echo "   - API требует аутентификацию (правильно для безопасности)"
    echo "   - Модели доступны в Ollama ($OLLAMA_MODELS шт.)"
    echo "   - Для просмотра моделей пользователи должны войти в систему"
    exit 0
else
    error "❌ Обнаружены критические проблемы ($CRITICAL_ISSUES)"
    echo
    echo "🔧 Рекомендации по устранению:"
    if [ "$STATUS_CODE" != "200" ]; then
        echo "   - Проверить доступность домена $DOMAIN"
    fi
    if [ "$HEALTH_STATUS" != "true" ]; then
        echo "   - Проверить статус OpenWebUI контейнера"
    fi
    if [ "$OLLAMA_MODELS" -eq 0 ]; then
        echo "   - Проверить подключение к Ollama и загруженные модели"
    fi
    exit 1
fi
