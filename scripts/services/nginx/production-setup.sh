#!/bin/bash

# ERNI-KI NGINX Production Setup Script
# Настройка nginx для продакшен среды с оптимизациями безопасности и производительности

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Конфигурация
NGINX_SSL_DIR="conf/nginx/ssl"
NGINX_CONF_DIR="conf/nginx"
BACKUP_DIR=".config-backup/nginx-$(date +%Y%m%d-%H%M%S)"

echo -e "${BLUE}🚀 ERNI-KI NGINX Production Setup${NC}"
echo "=================================================="

# Функция для логирования
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Создание резервной копии
create_backup() {
    log "Создание резервной копии текущей конфигурации..."
    mkdir -p "$BACKUP_DIR"

    if [ -d "$NGINX_CONF_DIR" ]; then
        cp -r "$NGINX_CONF_DIR" "$BACKUP_DIR/"
        log "Резервная копия создана: $BACKUP_DIR"
    else
        warn "Директория конфигурации nginx не найдена"
    fi
}

# Генерация DH параметров для улучшенной безопасности
generate_dhparam() {
    log "Проверка DH параметров..."

    if [ ! -f "$NGINX_SSL_DIR/dhparam.pem" ]; then
        log "Генерация DH параметров (это может занять несколько минут)..."
        mkdir -p "$NGINX_SSL_DIR"
        openssl dhparam -out "$NGINX_SSL_DIR/dhparam.pem" 2048
        log "DH параметры сгенерированы: $NGINX_SSL_DIR/dhparam.pem"
    else
        log "DH параметры уже существуют"
    fi
}

# Проверка SSL сертификатов
check_ssl_certificates() {
    log "Проверка SSL сертификатов..."

    if [ -f "$NGINX_SSL_DIR/nginx.crt" ] && [ -f "$NGINX_SSL_DIR/nginx.key" ]; then
        # Проверка валидности сертификата
        if openssl x509 -in "$NGINX_SSL_DIR/nginx.crt" -text -noout > /dev/null 2>&1; then
            local expiry=$(openssl x509 -in "$NGINX_SSL_DIR/nginx.crt" -noout -enddate | cut -d= -f2)
            log "SSL сертификат валиден до: $expiry"
        else
            error "SSL сертификат поврежден"
            return 1
        fi
    else
        warn "SSL сертификаты не найдены в $NGINX_SSL_DIR"
        warn "Убедитесь, что nginx.crt и nginx.key существуют"
    fi
}

# Тестирование конфигурации nginx
test_nginx_config() {
    log "Тестирование конфигурации nginx..."

    if docker exec erni-ki-nginx-1 nginx -t 2>/dev/null; then
        log "Конфигурация nginx корректна"
        return 0
    else
        error "Ошибка в конфигурации nginx"
        docker exec erni-ki-nginx-1 nginx -t
        return 1
    fi
}

# Применение продакшен конфигурации
apply_production_config() {
    log "Применение продакшен конфигурации..."

    # Создание резервной копии текущей конфигурации
    if [ -f "$NGINX_CONF_DIR/nginx.conf" ]; then
        cp "$NGINX_CONF_DIR/nginx.conf" "$BACKUP_DIR/nginx.conf.backup"
    fi

    # Копирование новой конфигурации
    if [ -f "$NGINX_CONF_DIR/nginx-production.conf" ]; then
        cp "$NGINX_CONF_DIR/nginx-production.conf" "$NGINX_CONF_DIR/nginx.conf"
        log "Продакшен конфигурация nginx применена"
    else
        error "Файл nginx-production.conf не найден"
        return 1
    fi
}

# Перезагрузка nginx
reload_nginx() {
    log "Перезагрузка nginx..."

    if docker exec erni-ki-nginx-1 nginx -s reload 2>/dev/null; then
        log "Nginx успешно перезагружен"
    else
        warn "Не удалось перезагрузить nginx, пробуем restart контейнера..."
        docker-compose restart nginx
        sleep 5

        if docker ps --filter "name=nginx" --format "{{.Status}}" | grep -q "Up"; then
            log "Nginx контейнер перезапущен успешно"
        else
            error "Не удалось перезапустить nginx"
            return 1
        fi
    fi
}

# Тестирование производительности
performance_test() {
    log "Тестирование производительности..."

    echo "HTTP тест:"
    time curl -s -o /dev/null -w "HTTP %{http_code} - %{time_total}s\n" http://localhost:8080/health

    echo "HTTPS тест:"
    time curl -s -o /dev/null -w "HTTP %{http_code} - %{time_total}s\n" -k https://localhost:443/health

    echo "SSL handshake тест:"
    echo | openssl s_client -connect localhost:443 -servername localhost 2>/dev/null | grep -E "(Protocol|Cipher)"
}

# Проверка security headers
check_security_headers() {
    log "Проверка security headers..."

    echo "Проверка HTTPS security headers:"
    curl -s -I -k https://localhost:443/health | grep -E "(Strict-Transport|X-Frame|X-Content|X-XSS|Referrer-Policy|Content-Security-Policy)"

    echo -e "\nПроверка HTTP security headers:"
    curl -s -I http://localhost:8080/health | grep -E "(X-Frame|X-Content|X-XSS|Referrer-Policy)"
}

# Основная функция
main() {
    log "Начало настройки nginx для продакшен среды"

    # Проверка, что мы в правильной директории
    if [ ! -f "compose.production.yml" ]; then
        error "Скрипт должен запускаться из корневой директории проекта ERNI-KI"
        exit 1
    fi

    # Выполнение шагов настройки
    create_backup
    generate_dhparam
    check_ssl_certificates

    # Применение конфигурации только если пользователь согласен
    echo -e "\n${YELLOW}Применить продакшен конфигурацию nginx? (y/N)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        apply_production_config

        if test_nginx_config; then
            reload_nginx
            sleep 3
            performance_test
            echo ""
            check_security_headers

            log "✅ Продакшен настройка nginx завершена успешно!"
            log "📊 Резервная копия сохранена в: $BACKUP_DIR"
            log "🔒 DH параметры: $NGINX_SSL_DIR/dhparam.pem"
            log "⚡ Производительность и безопасность оптимизированы"
        else
            error "Ошибка в конфигурации, откат изменений..."
            cp "$BACKUP_DIR/nginx.conf.backup" "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null || true
            docker exec erni-ki-nginx-1 nginx -s reload 2>/dev/null || docker-compose restart nginx
        fi
    else
        log "Применение конфигурации отменено пользователем"
        log "Для ручного применения: cp $NGINX_CONF_DIR/nginx-production.conf $NGINX_CONF_DIR/nginx.conf"
    fi
}

# Запуск основной функции
main "$@"
