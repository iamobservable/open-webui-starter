#!/bin/bash

# ERNI-KI Let's Encrypt SSL Setup с HTTP-01 Challenge
# Автор: Альтэон Шульц (Tech Lead-Мудрец)
# Версия: 1.0
# Дата: 2025-08-11
# ВНИМАНИЕ: Требует отключения Cloudflare проксирования!

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
DOMAIN="ki.erni-gruppe.ch"
EMAIL="admin@erni-ki.local"
ACME_HOME="$HOME/.acme.sh"
SSL_DIR="$(pwd)/conf/nginx/ssl"
WEBROOT_DIR="$(pwd)/data/certbot"
BACKUP_DIR="$(pwd)/.config-backup/ssl-http01-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$(pwd)/logs/ssl-http01-setup.log"

# Создание директорий
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$BACKUP_DIR"
mkdir -p "$WEBROOT_DIR"

# Проверка предварительных условий
check_prerequisites() {
    log "Проверка предварительных условий для HTTP-01 Challenge..."

    # Проверка acme.sh
    if [ ! -f "$ACME_HOME/acme.sh" ]; then
        error "acme.sh не найден. Установите его сначала."
    fi

    # Проверка Docker
    if ! command -v docker-compose &> /dev/null; then
        error "docker-compose не найден."
    fi

    # Проверка nginx контейнера
    if ! docker-compose ps nginx | grep -q "healthy"; then
        error "Nginx контейнер не запущен или не здоров."
    fi

    # ВАЖНОЕ ПРЕДУПРЕЖДЕНИЕ
    warning "ВНИМАНИЕ: HTTP-01 Challenge требует:"
    echo "1. Отключения Cloudflare проксирования (оранжевое облако → серое)"
    echo "2. Прямого доступа к серверу через порт 80"
    echo "3. A-записи домена должна указывать на реальный IP сервера"
    echo ""
    echo -n "Вы подтверждаете, что выполнили эти требования? (y/N): "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        error "Настройка отменена. Выполните требования и запустите скрипт снова."
    fi

    success "Предварительные условия проверены"
}

# Проверка доступности домена
check_domain_accessibility() {
    log "Проверка доступности домена $DOMAIN..."

    # Проверка DNS резолюции
    local resolved_ip=$(nslookup "$DOMAIN" | grep -A1 "Non-authoritative answer:" | grep "Address:" | awk '{print $2}' | head -1)
    log "Домен резолвится в: $resolved_ip"

    # Проверка доступности порта 80
    if curl -I --connect-timeout 10 "http://$DOMAIN/" >/dev/null 2>&1; then
        success "Домен доступен через HTTP"
    else
        error "Домен недоступен через HTTP. Проверьте DNS и Cloudflare настройки."
    fi
}

# Создание резервной копии
create_backup() {
    log "Создание резервной копии..."

    cp -r "$SSL_DIR" "$BACKUP_DIR/"
    success "Резервная копия создана: $BACKUP_DIR"
}

# Настройка nginx для webroot
setup_nginx_webroot() {
    log "Настройка nginx для webroot challenge..."

    # Создание временной конфигурации для ACME challenge
    local acme_conf="/tmp/acme-challenge.conf"
    cat > "$acme_conf" << EOF
# Временная конфигурация для Let's Encrypt HTTP-01 Challenge
location /.well-known/acme-challenge/ {
    root /var/www/certbot;
    try_files \$uri =404;
    access_log off;
    log_not_found off;
    
    # Заголовки для ACME challenge
    add_header Content-Type "text/plain" always;
    add_header Cache-Control "no-cache, no-store, must-revalidate" always;
}
EOF

    # Копирование конфигурации в nginx контейнер
    docker cp "$acme_conf" erni-ki-nginx-1:/etc/nginx/conf.d/acme-challenge.conf

    # Добавление volume mount для webroot (если не существует)
    if ! docker-compose config | grep -q "/var/www/certbot"; then
        warning "Webroot volume не настроен в docker-compose.yml"
        log "Создание временного bind mount..."
        
        # Создание временного контейнера с webroot
        docker-compose exec nginx mkdir -p /var/www/certbot
        docker cp "$WEBROOT_DIR/." erni-ki-nginx-1:/var/www/certbot/
    fi

    # Перезагрузка nginx
    if docker-compose exec nginx nginx -t; then
        docker-compose exec nginx nginx -s reload
        success "Nginx настроен для webroot challenge"
    else
        error "Ошибка в конфигурации nginx"
    fi

    # Очистка временного файла
    rm -f "$acme_conf"
}

# Получение сертификата Let's Encrypt
obtain_certificate() {
    log "Получение Let's Encrypt сертификата через HTTP-01 Challenge..."

    # Установка Let's Encrypt сервера
    "$ACME_HOME/acme.sh" --set-default-ca --server letsencrypt

    # Получение сертификата через webroot
    if "$ACME_HOME/acme.sh" --issue --webroot -w "$WEBROOT_DIR" -d "$DOMAIN" --email "$EMAIL" --force; then
        success "Сертификат успешно получен"
    else
        error "Ошибка получения сертификата"
    fi
}

# Установка сертификата
install_certificate() {
    log "Установка сертификата в nginx..."

    # Установка сертификата с правильными путями
    if "$ACME_HOME/acme.sh" --install-cert -d "$DOMAIN" \
        --cert-file "$SSL_DIR/nginx.crt" \
        --key-file "$SSL_DIR/nginx.key" \
        --fullchain-file "$SSL_DIR/nginx-fullchain.crt" \
        --ca-file "$SSL_DIR/nginx-ca.crt" \
        --reloadcmd "docker-compose exec nginx nginx -s reload"; then
        
        # Установка правильных прав доступа
        chmod 644 "$SSL_DIR"/*.crt
        chmod 600 "$SSL_DIR"/*.key
        
        success "Сертификат установлен в nginx"
    else
        error "Ошибка установки сертификата"
    fi
}

# Очистка временной конфигурации
cleanup_nginx_config() {
    log "Очистка временной конфигурации nginx..."

    # Удаление временной конфигурации ACME
    docker-compose exec nginx rm -f /etc/nginx/conf.d/acme-challenge.conf

    # Перезагрузка nginx
    if docker-compose exec nginx nginx -t; then
        docker-compose exec nginx nginx -s reload
        success "Временная конфигурация очищена"
    else
        warning "Ошибка при очистке конфигурации nginx"
    fi
}

# Проверка сертификата
verify_certificate() {
    log "Проверка установленного сертификата..."

    if [ -f "$SSL_DIR/nginx.crt" ]; then
        # Проверка издателя
        local issuer=$(openssl x509 -in "$SSL_DIR/nginx.crt" -noout -issuer | grep -o "CN=[^,]*" | cut -d= -f2)
        log "Издатель сертификата: $issuer"
        
        if echo "$issuer" | grep -q "Let's Encrypt"; then
            success "Сертификат выдан Let's Encrypt"
        else
            warning "Сертификат не от Let's Encrypt: $issuer"
        fi
        
        # Проверка срока действия
        local expiry_date=$(openssl x509 -in "$SSL_DIR/nginx.crt" -noout -enddate | cut -d= -f2)
        log "Сертификат действителен до: $expiry_date"
        
    else
        error "Файл сертификата не найден: $SSL_DIR/nginx.crt"
    fi
}

# Тестирование HTTPS
test_https() {
    log "Тестирование HTTPS доступа..."

    if curl -I "https://$DOMAIN/" --connect-timeout 10 >/dev/null 2>&1; then
        success "HTTPS доступ работает"
    else
        warning "HTTPS доступ недоступен"
    fi
}

# Генерация отчета
generate_report() {
    log "Генерация отчета..."
    
    local report_file="$(pwd)/logs/ssl-http01-report-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "ERNI-KI Let's Encrypt HTTP-01 Setup Report"
        echo "Generated: $(date)"
        echo "==========================================="
        echo ""
        
        echo "Configuration:"
        echo "- Domain: $DOMAIN"
        echo "- Method: HTTP-01 Challenge"
        echo "- Webroot: $WEBROOT_DIR"
        echo "- SSL Directory: $SSL_DIR"
        echo "- Backup: $BACKUP_DIR"
        echo ""
        
        echo "Certificate Information:"
        if [ -f "$SSL_DIR/nginx.crt" ]; then
            openssl x509 -in "$SSL_DIR/nginx.crt" -noout -subject -issuer -dates 2>/dev/null || echo "Error reading certificate"
        else
            echo "Certificate not found"
        fi
        echo ""
        
        echo "HTTPS Test:"
        if curl -I "https://$DOMAIN/" --connect-timeout 5 >/dev/null 2>&1; then
            echo "✓ HTTPS accessible"
        else
            echo "✗ HTTPS not accessible"
        fi
        echo ""
        
        echo "Important Notes:"
        echo "- Remember to re-enable Cloudflare proxying if needed"
        echo "- Monitor certificate expiry (90 days)"
        echo "- Set up automatic renewal"
        echo ""
        
    } > "$report_file"
    
    success "Отчет сохранен: $report_file"
    cat "$report_file"
}

# Основная функция
main() {
    echo -e "${CYAN}"
    echo "=================================================="
    echo "  ERNI-KI Let's Encrypt HTTP-01 Challenge Setup"
    echo "  ВНИМАНИЕ: Требует отключения Cloudflare проксирования!"
    echo "=================================================="
    echo -e "${NC}"

    check_prerequisites
    check_domain_accessibility
    create_backup
    setup_nginx_webroot
    obtain_certificate
    install_certificate
    cleanup_nginx_config
    verify_certificate
    test_https
    generate_report

    echo ""
    success "🎉 Let's Encrypt SSL сертификат (HTTP-01) успешно настроен!"
    echo ""
    log "Следующие шаги:"
    echo "1. Проверьте HTTPS доступ: https://$DOMAIN"
    echo "2. При необходимости включите обратно Cloudflare проксирование"
    echo "3. Настройте автоматическое обновление"
    echo ""
    log "Резервная копия: $BACKUP_DIR"
    log "Логи установки: $LOG_FILE"
}

# Запуск скрипта
main "$@" 2>&1 | tee -a "$LOG_FILE"
