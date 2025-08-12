#!/bin/bash

# ERNI-KI Let's Encrypt SSL Setup с Cloudflare DNS Challenge
# Автор: Альтэон Шульц (Tech Lead-Мудрец)
# Версия: 1.0
# Дата: 2025-08-11

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
BACKUP_DIR="$(pwd)/.config-backup/ssl-letsencrypt-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$(pwd)/logs/ssl-setup.log"

# Создание директории для логов
mkdir -p "$(dirname "$LOG_FILE")"

# Проверка зависимостей
check_dependencies() {
    log "Проверка зависимостей..."

    # Проверка Docker
    if ! command -v docker-compose &> /dev/null; then
        error "docker-compose не найден. Установите Docker Compose."
    fi

    # Проверка curl
    if ! command -v curl &> /dev/null; then
        error "curl не найден. Установите curl."
    fi

    # Проверка openssl
    if ! command -v openssl &> /dev/null; then
        error "openssl не найден. Установите openssl."
    fi

    # Проверка директории SSL
    if [ ! -d "$SSL_DIR" ]; then
        error "Директория SSL не найдена: $SSL_DIR"
    fi

    success "Все зависимости найдены"
}

# Проверка Cloudflare API токена
check_cloudflare_credentials() {
    log "Проверка Cloudflare API токена..."

    if [ -z "${CF_Token:-}" ] && [ -z "${CF_Key:-}" ]; then
        error "Cloudflare API токен не найден. Установите переменную CF_Token или CF_Key и CF_Email"
    fi

    if [ -n "${CF_Token:-}" ]; then
        log "Используется Cloudflare API Token (рекомендуется)"
        # Тест API токена
        if ! curl -s -H "Authorization: Bearer $CF_Token" \
             -H "Content-Type: application/json" \
             "https://api.cloudflare.com/client/v4/user/tokens/verify" | grep -q '"success":true'; then
            error "Cloudflare API токен недействителен"
        fi
    elif [ -n "${CF_Key:-}" ] && [ -n "${CF_Email:-}" ]; then
        log "Используется Cloudflare Global API Key"
        # Тест Global API Key
        if ! curl -s -H "X-Auth-Email: $CF_Email" \
             -H "X-Auth-Key: $CF_Key" \
             -H "Content-Type: application/json" \
             "https://api.cloudflare.com/client/v4/user" | grep -q '"success":true'; then
            error "Cloudflare Global API Key недействителен"
        fi
    else
        error "Неполные данные Cloudflare API. Требуется CF_Token или (CF_Key + CF_Email)"
    fi

    success "Cloudflare API токен действителен"
}

# Установка acme.sh
install_acme_sh() {
    log "Установка acme.sh..."

    if [ ! -f "$ACME_HOME/acme.sh" ]; then
        log "Загрузка и установка acme.sh..."
        curl https://get.acme.sh | sh -s email="$EMAIL"
        
        # Перезагрузка переменных окружения
        source "$HOME/.bashrc" 2>/dev/null || true
        
        if [ ! -f "$ACME_HOME/acme.sh" ]; then
            error "Ошибка установки acme.sh"
        fi
    else
        log "acme.sh уже установлен"
    fi

    # Обновление acme.sh до последней версии
    "$ACME_HOME/acme.sh" --upgrade

    success "acme.sh установлен и обновлен"
}

# Создание резервной копии
create_backup() {
    log "Создание резервной копии текущих сертификатов..."

    mkdir -p "$BACKUP_DIR"
    
    if [ -f "$SSL_DIR/nginx.crt" ]; then
        cp "$SSL_DIR"/*.crt "$BACKUP_DIR/" 2>/dev/null || true
        cp "$SSL_DIR"/*.key "$BACKUP_DIR/" 2>/dev/null || true
        cp "$SSL_DIR"/*.pem "$BACKUP_DIR/" 2>/dev/null || true
        success "Резервная копия создана: $BACKUP_DIR"
    else
        warning "Существующие сертификаты не найдены"
    fi
}

# Получение сертификата Let's Encrypt
obtain_certificate() {
    log "Получение Let's Encrypt сертификата для домена: $DOMAIN"

    # Установка Let's Encrypt сервера
    "$ACME_HOME/acme.sh" --set-default-ca --server letsencrypt

    # Получение сертификата через DNS-01 challenge с Cloudflare API
    if "$ACME_HOME/acme.sh" --issue --dns dns_cf -d "$DOMAIN" --email "$EMAIL" --force; then
        success "Сертификат успешно получен"
    else
        error "Ошибка получения сертификата"
    fi
}

# Установка сертификата
install_certificate() {
    log "Установка сертификата в nginx..."

    # Создание временной директории для новых сертификатов
    TEMP_SSL_DIR="/tmp/ssl-new-$(date +%s)"
    mkdir -p "$TEMP_SSL_DIR"

    # Установка сертификата с правильными путями
    if "$ACME_HOME/acme.sh" --install-cert -d "$DOMAIN" \
        --cert-file "$TEMP_SSL_DIR/nginx.crt" \
        --key-file "$TEMP_SSL_DIR/nginx.key" \
        --fullchain-file "$TEMP_SSL_DIR/nginx-fullchain.crt" \
        --ca-file "$TEMP_SSL_DIR/nginx-ca.crt"; then
        
        # Копирование сертификатов в рабочую директорию
        cp "$TEMP_SSL_DIR"/* "$SSL_DIR/"
        
        # Установка правильных прав доступа
        chmod 644 "$SSL_DIR"/*.crt
        chmod 600 "$SSL_DIR"/*.key
        
        # Очистка временной директории
        rm -rf "$TEMP_SSL_DIR"
        
        success "Сертификат установлен в nginx"
    else
        rm -rf "$TEMP_SSL_DIR"
        error "Ошибка установки сертификата"
    fi
}

# Проверка сертификата
verify_certificate() {
    log "Проверка установленного сертификата..."

    if [ -f "$SSL_DIR/nginx.crt" ]; then
        # Проверка срока действия
        local expiry_date=$(openssl x509 -in "$SSL_DIR/nginx.crt" -noout -enddate | cut -d= -f2)
        log "Сертификат действителен до: $expiry_date"
        
        # Проверка домена
        local cert_domain=$(openssl x509 -in "$SSL_DIR/nginx.crt" -noout -subject | grep -o "CN=[^,]*" | cut -d= -f2)
        if [ "$cert_domain" = "$DOMAIN" ]; then
            success "Сертификат выдан для правильного домена: $cert_domain"
        else
            warning "Домен в сертификате ($cert_domain) не соответствует ожидаемому ($DOMAIN)"
        fi
        
        # Проверка издателя
        local issuer=$(openssl x509 -in "$SSL_DIR/nginx.crt" -noout -issuer | grep -o "CN=[^,]*" | cut -d= -f2)
        log "Издатель сертификата: $issuer"
        
    else
        error "Файл сертификата не найден: $SSL_DIR/nginx.crt"
    fi
}

# Перезагрузка nginx
reload_nginx() {
    log "Перезагрузка nginx..."

    # Проверка конфигурации nginx
    if docker-compose exec -T nginx nginx -t; then
        # Перезагрузка nginx
        if docker-compose exec -T nginx nginx -s reload; then
            success "Nginx успешно перезагружен"
        else
            warning "Ошибка перезагрузки nginx, перезапуск контейнера..."
            docker-compose restart nginx
        fi
    else
        error "Ошибка в конфигурации nginx"
    fi
}

# Настройка автоматического обновления
setup_auto_renewal() {
    log "Настройка автоматического обновления сертификатов..."

    # Создание hook скрипта для перезагрузки nginx
    local hook_script="$ACME_HOME/nginx-reload-hook.sh"
    
    cat > "$hook_script" << 'EOF'
#!/bin/bash
# Hook скрипт для перезагрузки nginx после обновления сертификата

cd "$(dirname "$0")/../.."

# Логирование
echo "$(date): Certificate renewal hook executed" >> logs/ssl-renewal.log

# Перезагрузка nginx
if docker-compose exec -T nginx nginx -s reload 2>/dev/null; then
    echo "$(date): Nginx reloaded successfully after certificate renewal" >> logs/ssl-renewal.log
else
    echo "$(date): Failed to reload nginx, restarting container" >> logs/ssl-renewal.log
    docker-compose restart nginx
fi
EOF

    chmod +x "$hook_script"

    # Обновление acme.sh конфигурации для использования hook
    "$ACME_HOME/acme.sh" --install-cert -d "$DOMAIN" \
        --cert-file "$SSL_DIR/nginx.crt" \
        --key-file "$SSL_DIR/nginx.key" \
        --fullchain-file "$SSL_DIR/nginx-fullchain.crt" \
        --ca-file "$SSL_DIR/nginx-ca.crt" \
        --reloadcmd "$hook_script"

    success "Hook скрипт для автообновления настроен"
}

# Основная функция
main() {
    echo -e "${CYAN}"
    echo "=================================================="
    echo "  ERNI-KI Let's Encrypt SSL Setup"
    echo "  Cloudflare DNS Challenge"
    echo "=================================================="
    echo -e "${NC}"

    check_dependencies
    check_cloudflare_credentials
    install_acme_sh
    create_backup
    obtain_certificate
    install_certificate
    verify_certificate
    reload_nginx
    setup_auto_renewal

    echo ""
    success "🎉 Let's Encrypt SSL сертификат успешно настроен!"
    echo ""
    log "Следующие шаги:"
    echo "1. Проверьте HTTPS доступ: https://$DOMAIN"
    echo "2. Проверьте SSL рейтинг: https://www.ssllabs.com/ssltest/"
    echo "3. Сертификат будет автоматически обновляться каждые 60 дней"
    echo ""
    log "Резервная копия старых сертификатов: $BACKUP_DIR"
    log "Логи установки: $LOG_FILE"
}

# Запуск скрипта
main "$@" 2>&1 | tee -a "$LOG_FILE"
