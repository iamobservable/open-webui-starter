#!/bin/bash

# Тестирование конфигурации nginx для ERNI-KI
# Проверяет синтаксис и SSL настройки

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции для логирования
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Проверка синтаксиса конфигурации
test_nginx_syntax() {
    log "Проверка синтаксиса конфигурации nginx..."
    
    # Проверка через Docker если nginx запущен
    if docker compose ps nginx 2>/dev/null | grep -q "Up"; then
        if docker compose exec nginx nginx -t 2>/dev/null; then
            success "Синтаксис конфигурации nginx корректен"
            return 0
        else
            error "Ошибка в синтаксисе конфигурации nginx"
            docker compose exec nginx nginx -t
            return 1
        fi
    else
        warning "Nginx не запущен, проверка синтаксиса пропущена"
        return 0
    fi
}

# Проверка SSL сертификатов
test_ssl_certificates() {
    log "Проверка SSL сертификатов..."
    
    local ssl_dir="conf/nginx/ssl"
    local cert_file="$ssl_dir/nginx.crt"
    local key_file="$ssl_dir/nginx.key"
    local fullchain_file="$ssl_dir/nginx-fullchain.crt"
    
    # Проверка основного сертификата
    if [ -f "$cert_file" ]; then
        if openssl x509 -in "$cert_file" -noout -text >/dev/null 2>&1; then
            success "Основной сертификат валиден"
            
            # Показать информацию о сертификате
            echo ""
            log "Информация о сертификате:"
            openssl x509 -in "$cert_file" -noout -subject -issuer -dates
            echo ""
        else
            error "Основной сертификат поврежден"
            return 1
        fi
    else
        warning "Основной сертификат не найден: $cert_file"
    fi
    
    # Проверка приватного ключа
    if [ -f "$key_file" ]; then
        if openssl rsa -in "$key_file" -check -noout >/dev/null 2>&1; then
            success "Приватный ключ валиден"
        else
            error "Приватный ключ поврежден"
            return 1
        fi
    else
        warning "Приватный ключ не найден: $key_file"
    fi
    
    # Проверка fullchain сертификата (для Let's Encrypt)
    if [ -f "$fullchain_file" ]; then
        if openssl x509 -in "$fullchain_file" -noout -text >/dev/null 2>&1; then
            success "Fullchain сертификат валиден"
        else
            warning "Fullchain сертификат поврежден"
        fi
    else
        log "Fullchain сертификат не найден (будет создан при получении Let's Encrypt)"
    fi
    
    # Проверка соответствия ключа и сертификата
    if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
        local cert_modulus=$(openssl x509 -noout -modulus -in "$cert_file" 2>/dev/null | openssl md5)
        local key_modulus=$(openssl rsa -noout -modulus -in "$key_file" 2>/dev/null | openssl md5)
        
        if [ "$cert_modulus" = "$key_modulus" ]; then
            success "Сертификат и ключ соответствуют друг другу"
        else
            error "Сертификат и ключ не соответствуют друг другу"
            return 1
        fi
    fi
}

# Проверка HTTPS доступности
test_https_access() {
    log "Проверка HTTPS доступности..."
    
    local domain="ki.erni-gruppe.ch"
    
    # Проверка локального HTTPS
    if curl -k -I "https://localhost:443/" --connect-timeout 5 >/dev/null 2>&1; then
        success "Локальный HTTPS доступен"
    else
        warning "Локальный HTTPS недоступен"
    fi
    
    # Проверка HTTPS через домен
    if curl -k -I "https://$domain/" --connect-timeout 5 >/dev/null 2>&1; then
        success "HTTPS через домен доступен"
        
        # Показать заголовки ответа
        echo ""
        log "HTTP заголовки ответа:"
        curl -k -I "https://$domain/" --connect-timeout 5 2>/dev/null | head -10
        echo ""
    else
        warning "HTTPS через домен недоступен"
    fi
}

# Проверка SSL конфигурации
test_ssl_configuration() {
    log "Проверка SSL конфигурации..."
    
    local domain="ki.erni-gruppe.ch"
    
    # Проверка SSL соединения
    if echo | openssl s_client -connect "$domain:443" -servername "$domain" >/dev/null 2>&1; then
        success "SSL соединение установлено"
        
        # Показать детали SSL
        echo ""
        log "Детали SSL соединения:"
        echo | openssl s_client -connect "$domain:443" -servername "$domain" 2>/dev/null | grep -E "(Protocol|Cipher|Verify)"
        echo ""
    else
        warning "Не удалось установить SSL соединение"
    fi
}

# Проверка безопасности заголовков
test_security_headers() {
    log "Проверка заголовков безопасности..."
    
    local domain="ki.erni-gruppe.ch"
    
    if curl -k -I "https://$domain/" --connect-timeout 5 >/dev/null 2>&1; then
        local headers=$(curl -k -I "https://$domain/" --connect-timeout 5 2>/dev/null)
        
        # Проверка HSTS
        if echo "$headers" | grep -qi "strict-transport-security"; then
            success "HSTS заголовок присутствует"
        else
            warning "HSTS заголовок отсутствует"
        fi
        
        # Проверка X-Frame-Options
        if echo "$headers" | grep -qi "x-frame-options"; then
            success "X-Frame-Options заголовок присутствует"
        else
            warning "X-Frame-Options заголовок отсутствует"
        fi
        
        # Проверка X-Content-Type-Options
        if echo "$headers" | grep -qi "x-content-type-options"; then
            success "X-Content-Type-Options заголовок присутствует"
        else
            warning "X-Content-Type-Options заголовок отсутствует"
        fi
        
        # Проверка CSP
        if echo "$headers" | grep -qi "content-security-policy"; then
            success "Content-Security-Policy заголовок присутствует"
        else
            warning "Content-Security-Policy заголовок отсутствует"
        fi
    else
        warning "Не удалось получить заголовки для проверки безопасности"
    fi
}

# Генерация отчета
generate_report() {
    echo ""
    log "=== ОТЧЕТ О ТЕСТИРОВАНИИ NGINX SSL КОНФИГУРАЦИИ ==="
    echo ""
    
    log "Рекомендации:"
    echo "1. После получения Let's Encrypt сертификата перезапустите nginx"
    echo "2. Проверьте SSL рейтинг на https://www.ssllabs.com/ssltest/"
    echo "3. Убедитесь, что все сервисы доступны через HTTPS"
    echo "4. Настройте мониторинг срока действия сертификатов"
    echo ""
    
    log "Полезные команды:"
    echo "- Проверка сертификата: openssl x509 -in conf/nginx/ssl/nginx.crt -text -noout"
    echo "- Перезагрузка nginx: docker compose restart nginx"
    echo "- Проверка логов: docker compose logs nginx"
    echo "- Тест SSL: echo | openssl s_client -connect ki.erni-gruppe.ch:443"
}

# Основная функция
main() {
    echo -e "${BLUE}"
    echo "=============================================="
    echo "  ERNI-KI Nginx SSL Configuration Test"
    echo "=============================================="
    echo -e "${NC}"
    
    # Проверка, что мы в корне проекта
    if [ ! -f "compose.yml" ] && [ ! -f "compose.yml.example" ]; then
        error "Скрипт должен запускаться из корня проекта ERNI-KI"
        exit 1
    fi
    
    test_nginx_syntax
    test_ssl_certificates
    test_https_access
    test_ssl_configuration
    test_security_headers
    generate_report
    
    success "Тестирование завершено!"
}

# Запуск скрипта
main "$@"
