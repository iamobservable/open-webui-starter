#!/bin/bash

# ERNI-KI Nginx Configuration Update for Let's Encrypt
# Автор: Альтэон Шульц (Tech Lead-Мудрец)
# Версия: 1.0
# Дата: 2025-08-11
# Назначение: Обновление конфигурации nginx для использования Let's Encrypt сертификатов

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Функции логирования
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

# Конфигурация
PROJECT_ROOT="$(pwd)"
NGINX_CONF_DIR="$PROJECT_ROOT/conf/nginx"
NGINX_DEFAULT_CONF="$NGINX_CONF_DIR/conf.d/default.conf"
SSL_DIR="$NGINX_CONF_DIR/ssl"
BACKUP_DIR="$PROJECT_ROOT/.config-backup/nginx-letsencrypt-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$PROJECT_ROOT/logs/nginx-letsencrypt-update.log"

# Создание директорий
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$BACKUP_DIR"

# Проверка текущей конфигурации
check_current_config() {
    log "Проверка текущей конфигурации nginx..."

    if [ ! -f "$NGINX_DEFAULT_CONF" ]; then
        error "Файл конфигурации nginx не найден: $NGINX_DEFAULT_CONF"
    fi

    # Проверка SSL настроек
    if grep -q "ssl_certificate.*nginx-fullchain.crt" "$NGINX_DEFAULT_CONF"; then
        success "Конфигурация уже настроена для Let's Encrypt (fullchain)"
    elif grep -q "ssl_certificate.*nginx.crt" "$NGINX_DEFAULT_CONF"; then
        warning "Конфигурация использует простой сертификат, требуется обновление"
        return 1
    else
        error "SSL конфигурация не найдена в nginx"
    fi

    # Проверка OCSP stapling
    if grep -q "ssl_stapling on" "$NGINX_DEFAULT_CONF"; then
        success "OCSP stapling включен"
    else
        warning "OCSP stapling не настроен"
    fi

    return 0
}

# Создание резервной копии
create_backup() {
    log "Создание резервной копии конфигурации nginx..."

    cp -r "$NGINX_CONF_DIR" "$BACKUP_DIR/"
    success "Резервная копия создана: $BACKUP_DIR"
}

# Проверка Let's Encrypt сертификатов
check_letsencrypt_certificates() {
    log "Проверка Let's Encrypt сертификатов..."

    local required_files=(
        "$SSL_DIR/nginx.crt"
        "$SSL_DIR/nginx.key"
        "$SSL_DIR/nginx-fullchain.crt"
        "$SSL_DIR/nginx-ca.crt"
    )

    for file in "${required_files[@]}"; do
        if [ -f "$file" ]; then
            success "Найден: $(basename "$file")"
        else
            error "Отсутствует: $file"
        fi
    done

    # Проверка, что сертификат от Let's Encrypt
    if openssl x509 -in "$SSL_DIR/nginx.crt" -noout -issuer | grep -q "Let's Encrypt"; then
        success "Сертификат выдан Let's Encrypt"
    else
        local issuer=$(openssl x509 -in "$SSL_DIR/nginx.crt" -noout -issuer 2>/dev/null || echo "Unknown")
        warning "Сертификат не от Let's Encrypt. Издатель: $issuer"
    fi

    # Проверка срока действия
    local expiry_date=$(openssl x509 -in "$SSL_DIR/nginx.crt" -noout -enddate | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s)
    local current_epoch=$(date +%s)
    local days_left=$(( (expiry_epoch - current_epoch) / 86400 ))

    if [ $days_left -gt 0 ]; then
        success "Сертификат действителен еще $days_left дней"
    else
        error "Сертификат истек $((days_left * -1)) дней назад"
    fi
}

# Обновление конфигурации nginx
update_nginx_config() {
    log "Обновление конфигурации nginx для Let's Encrypt..."

    # Проверка, нужно ли обновление
    if check_current_config; then
        log "Конфигурация уже оптимизирована для Let's Encrypt"
        return 0
    fi

    # Обновление путей к сертификатам
    log "Обновление путей к сертификатам..."
    
    # Замена ssl_certificate на fullchain версию
    sed -i 's|ssl_certificate /etc/nginx/ssl/nginx\.crt;|ssl_certificate /etc/nginx/ssl/nginx-fullchain.crt;|g' "$NGINX_DEFAULT_CONF"
    
    # Добавление OCSP stapling если отсутствует
    if ! grep -q "ssl_stapling on" "$NGINX_DEFAULT_CONF"; then
        log "Добавление OCSP stapling конфигурации..."
        
        # Найти строку с ssl_session_tickets и добавить после неё OCSP настройки
        sed -i '/ssl_session_tickets off;/a\\n  # OCSP Stapling для быстрой проверки сертификатов\n  ssl_stapling on;\n  ssl_stapling_verify on;\n  ssl_trusted_certificate /etc/nginx/ssl/nginx-ca.crt;\n  resolver 1.1.1.1 1.0.0.1 valid=300s;\n  resolver_timeout 5s;' "$NGINX_DEFAULT_CONF"
    fi

    success "Конфигурация nginx обновлена для Let's Encrypt"
}

# Проверка конфигурации nginx
test_nginx_config() {
    log "Проверка конфигурации nginx..."

    if docker-compose exec -T nginx nginx -t; then
        success "Конфигурация nginx корректна"
        return 0
    else
        error "Ошибка в конфигурации nginx"
        return 1
    fi
}

# Перезагрузка nginx
reload_nginx() {
    log "Перезагрузка nginx..."

    if docker-compose exec -T nginx nginx -s reload; then
        success "Nginx успешно перезагружен"
    else
        warning "Ошибка перезагрузки nginx, перезапуск контейнера..."
        docker-compose restart nginx
        
        # Проверка статуса после перезапуска
        sleep 5
        if docker-compose ps nginx | grep -q "healthy"; then
            success "Nginx контейнер перезапущен и здоров"
        else
            error "Nginx контейнер не запустился корректно"
        fi
    fi
}

# Тестирование HTTPS
test_https_access() {
    log "Тестирование HTTPS доступа..."

    local domain="ki.erni-gruppe.ch"
    
    # Тест локального доступа
    if curl -k -I "https://localhost/" --connect-timeout 5 >/dev/null 2>&1; then
        success "Локальный HTTPS доступ работает"
    else
        warning "Локальный HTTPS доступ недоступен"
    fi

    # Тест доступа по домену
    if curl -I "https://$domain/" --connect-timeout 5 >/dev/null 2>&1; then
        success "HTTPS доступ по домену работает"
    else
        warning "HTTPS доступ по домену недоступен (возможно, проблемы с DNS или сертификатом)"
    fi

    # Тест SSL соединения
    if echo | openssl s_client -connect "$domain:443" -servername "$domain" >/dev/null 2>&1; then
        success "SSL соединение установлено успешно"
    else
        warning "Проблемы с SSL соединением"
    fi
}

# Проверка SSL рейтинга
check_ssl_rating() {
    log "Проверка SSL конфигурации..."

    local domain="ki.erni-gruppe.ch"
    
    # Проверка поддерживаемых протоколов
    log "Проверка поддерживаемых SSL протоколов..."
    
    if echo | openssl s_client -connect "$domain:443" -tls1_2 >/dev/null 2>&1; then
        success "TLS 1.2 поддерживается"
    else
        warning "TLS 1.2 не поддерживается"
    fi

    if echo | openssl s_client -connect "$domain:443" -tls1_3 >/dev/null 2>&1; then
        success "TLS 1.3 поддерживается"
    else
        warning "TLS 1.3 не поддерживается"
    fi

    # Проверка HSTS заголовка
    if curl -k -I "https://$domain/" 2>/dev/null | grep -q "Strict-Transport-Security"; then
        success "HSTS заголовок настроен"
    else
        warning "HSTS заголовок отсутствует"
    fi
}

# Генерация отчета
generate_report() {
    log "Генерация отчета обновления nginx..."
    
    local report_file="$PROJECT_ROOT/logs/nginx-letsencrypt-update-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "ERNI-KI Nginx Let's Encrypt Update Report"
        echo "Generated: $(date)"
        echo "=========================================="
        echo ""
        
        echo "Configuration Files:"
        echo "- Nginx config: $NGINX_DEFAULT_CONF"
        echo "- SSL directory: $SSL_DIR"
        echo "- Backup: $BACKUP_DIR"
        echo ""
        
        echo "Certificate Information:"
        if [ -f "$SSL_DIR/nginx.crt" ]; then
            openssl x509 -in "$SSL_DIR/nginx.crt" -noout -subject -issuer -dates 2>/dev/null || echo "Error reading certificate"
        else
            echo "Certificate not found"
        fi
        echo ""
        
        echo "Nginx Configuration Check:"
        docker-compose exec -T nginx nginx -t 2>&1 || echo "Configuration test failed"
        echo ""
        
        echo "Container Status:"
        docker-compose ps nginx || echo "Container status check failed"
        echo ""
        
        echo "Next Steps:"
        echo "1. Test HTTPS access: https://ki.erni-gruppe.ch/"
        echo "2. Check SSL rating: https://www.ssllabs.com/ssltest/"
        echo "3. Monitor certificate expiry"
        echo ""
        
    } > "$report_file"
    
    success "Отчет сохранен: $report_file"
    cat "$report_file"
}

# Основная функция
main() {
    echo -e "${CYAN}"
    echo "=================================================="
    echo "  ERNI-KI Nginx Let's Encrypt Configuration"
    echo "  Обновление для валидных SSL сертификатов"
    echo "=================================================="
    echo -e "${NC}"

    create_backup
    check_letsencrypt_certificates
    update_nginx_config
    
    if test_nginx_config; then
        reload_nginx
        test_https_access
        check_ssl_rating
        generate_report
        
        echo ""
        success "🎉 Nginx успешно настроен для Let's Encrypt!"
        echo ""
        log "Следующие шаги:"
        echo "1. Проверьте HTTPS доступ: https://ki.erni-gruppe.ch/"
        echo "2. Проверьте SSL рейтинг: https://www.ssllabs.com/ssltest/"
        echo "3. Настройте мониторинг сертификатов"
        echo ""
        log "Резервная копия: $BACKUP_DIR"
    else
        error "Ошибка в конфигурации nginx. Проверьте логи и восстановите из резервной копии при необходимости."
    fi
}

# Запуск скрипта
main "$@" 2>&1 | tee -a "$LOG_FILE"
