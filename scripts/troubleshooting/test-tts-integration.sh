#!/bin/bash

# Скрипт тестирования интеграции EdgeTTS с OpenWebUI
# Автор: Альтэон Шульц (ERNI-KI Tech Lead)

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

# Проверка статуса сервисов
check_services() {
    log "Проверка статуса сервисов..."
    
    # EdgeTTS
    if docker-compose ps edgetts | grep -q "healthy"; then
        success "EdgeTTS сервис работает (healthy)"
    else
        error "EdgeTTS сервис не работает"
        return 1
    fi
    
    # OpenWebUI
    if docker-compose ps openwebui | grep -q "healthy"; then
        success "OpenWebUI сервис работает (healthy)"
    else
        error "OpenWebUI сервис не работает"
        return 1
    fi
}

# Тест EdgeTTS API
test_edgetts_api() {
    log "Тестирование EdgeTTS API..."
    
    # Тест получения списка голосов
    log "Проверка доступных голосов..."
    if curl -s -H "Authorization: Bearer your_api_key_here" \
        http://localhost:5050/v1/audio/voices | jq -e '.voices' >/dev/null 2>&1; then
        success "API голосов работает"
        
        # Показать доступные голоса
        echo "Доступные голоса:"
        curl -s -H "Authorization: Bearer your_api_key_here" \
            http://localhost:5050/v1/audio/voices | jq -r '.voices[] | "- \(.id): \(.name)"'
    else
        error "API голосов не работает"
        return 1
    fi
    
    # Тест синтеза речи
    log "Тестирование синтеза речи..."
    local test_file="/tmp/tts_test_$(date +%s).mp3"
    
    if curl -s -X POST http://localhost:5050/v1/audio/speech \
        -H "Authorization: Bearer your_api_key_here" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "tts-1",
            "input": "Тест интеграции EdgeTTS с OpenWebUI успешно выполнен!",
            "voice": "en-US-EmmaMultilingualNeural"
        }' \
        --output "$test_file"; then
        
        # Проверка размера файла
        local file_size=$(stat -c%s "$test_file" 2>/dev/null || echo "0")
        if [ "$file_size" -gt 1000 ]; then
            success "Синтез речи работает (файл: $file_size байт)"
            
            # Проверка формата файла
            if file "$test_file" | grep -q "MPEG"; then
                success "Файл в корректном MP3 формате"
            else
                warning "Файл создан, но формат может быть некорректным"
            fi
        else
            error "Файл слишком маленький или пустой"
            return 1
        fi
        
        # Очистка
        rm -f "$test_file"
    else
        error "Синтез речи не работает"
        return 1
    fi
}

# Проверка конфигурации OpenWebUI
check_openwebui_config() {
    log "Проверка конфигурации OpenWebUI..."
    
    echo "=== TTS настройки в OpenWebUI ==="
    grep -E "AUDIO_TTS" env/openwebui.env || true
    
    # Проверка ключевых параметров
    if grep -q "AUDIO_TTS_ENGINE=openai" env/openwebui.env; then
        success "TTS движок настроен на OpenAI (совместимый)"
    else
        error "TTS движок не настроен"
    fi
    
    if grep -q "AUDIO_TTS_OPENAI_API_BASE_URL=http://edgetts:5050/v1" env/openwebui.env; then
        success "API URL EdgeTTS настроен корректно"
    else
        error "API URL EdgeTTS не настроен"
    fi
    
    if grep -q "AUDIO_TTS_OPENAI_API_KEY=your_api_key_here" env/openwebui.env; then
        success "API ключ настроен корректно"
    else
        error "API ключ не настроен"
    fi
}

# Проверка конфигурации EdgeTTS
check_edgetts_config() {
    log "Проверка конфигурации EdgeTTS..."
    
    echo "=== EdgeTTS настройки ==="
    cat env/edgetts.env
    
    if grep -q "DEFAULT_VOICE=en-US-EmmaMultilingualNeural" env/edgetts.env; then
        success "Голос по умолчанию настроен корректно"
    else
        warning "Голос по умолчанию может быть не настроен"
    fi
}

# Тест подключения из OpenWebUI к EdgeTTS
test_internal_connectivity() {
    log "Тестирование внутреннего подключения OpenWebUI -> EdgeTTS..."
    
    if docker-compose exec -T openwebui curl -s -f \
        -H "Authorization: Bearer your_api_key_here" \
        http://edgetts:5050/v1/audio/voices >/dev/null; then
        success "OpenWebUI может подключиться к EdgeTTS"
    else
        error "OpenWebUI не может подключиться к EdgeTTS"
        return 1
    fi
}

# Основная функция
main() {
    echo "=================================================="
    echo "🎤 Тест интеграции EdgeTTS с OpenWebUI"
    echo "=================================================="
    echo ""
    
    # Выполнение тестов
    check_services || exit 1
    echo ""
    
    check_edgetts_config
    echo ""
    
    check_openwebui_config
    echo ""
    
    test_edgetts_api || exit 1
    echo ""
    
    test_internal_connectivity || exit 1
    echo ""
    
    echo "=================================================="
    success "🎉 Все тесты пройдены успешно!"
    echo ""
    echo "📋 Следующие шаги:"
    echo "1. Откройте OpenWebUI: https://diz.zone"
    echo "2. Войдите с учетными данными:"
    echo "   Email: diz-admin@proton.me"
    echo "   Пароль: testpass"
    echo "3. В настройках найдите раздел Audio/TTS"
    echo "4. Проверьте что TTS включен и работает"
    echo "5. Протестируйте синтез речи в чате"
    echo "=================================================="
}

# Запуск
main "$@"
