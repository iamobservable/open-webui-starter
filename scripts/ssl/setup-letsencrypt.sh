#!/bin/bash

# ERNI-KI Let's Encrypt SSL Setup Script
# Настройка SSL сертификатов Let's Encrypt для домена ki.erni-gruppe.ch
# Использует acme.sh с DNS-01 challenge через Cloudflare API

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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
    exit 1
}

# Конфигурация
DOMAIN="ki.erni-gruppe.ch"
EMAIL="admin@gmail.com"
ACME_HOME="$HOME/.acme.sh"
SSL_DIR="$(pwd)/conf/nginx/ssl"
BACKUP_DIR="$(pwd)/.config-backup/ssl-letsencrypt-$(date +%Y%m%d-%H%M%S)"

# Проверка зависимостей
check_dependencies() {
    log "Проверка зависимостей..."

    if [ ! -f "$ACME_HOME/acme.sh" ]; then
        error "acme.sh не найден. Установите его сначала: curl https://get.acme.sh | sh"
    fi

    if [ ! -d "$SSL_DIR" ]; then
        error "Директория SSL не найдена: $SSL_DIR"
    fi

    success "Все зависимости найдены"
}

# Проверка переменных окружения Cyon
check_cyon_credentials() {
    log "Проверка Cyon API credentials..."

    if [ -z "${CY_Username:-}" ] || [ -z "${CY_Password:-}" ]; then
        error "Не найдены Cyon API credentials. Установите переменные:
        - CY_Username: Логин от my.cyon.ch (например: kontakt@erni-gruppe.ch)
        - CY_Password: Пароль от my.cyon.ch
        - CY_OTP_Secret: (опционально) OTP токен для 2FA"
    fi

    log "Используется Cyon DNS API"
    export CY_Username="$CY_Username"
    export CY_Password="$CY_Password"

    if [ -n "${CY_OTP_Secret:-}" ]; then
        log "2FA включена"
        export CY_OTP_Secret="$CY_OTP_Secret"
    fi

    success "Cyon credentials настроены"
}

# Создание резервной копии
create_backup() {
    log "Создание резервной копии текущих сертификатов..."

    mkdir -p "$BACKUP_DIR"

    if [ -f "$SSL_DIR/nginx.crt" ]; then
        cp "$SSL_DIR/nginx.crt" "$BACKUP_DIR/"
        cp "$SSL_DIR/nginx.key" "$BACKUP_DIR/"
        log "Резервная копия создана в: $BACKUP_DIR"
    else
        warning "Текущие сертификаты не найдены"
    fi
}

# Получение сертификата Let's Encrypt
obtain_certificate() {
    log "Получение Let's Encrypt сертификата для домена: $DOMAIN"

    # Установка Let's Encrypt сервера
    "$ACME_HOME/acme.sh" --set-default-ca --server letsencrypt

    # Получение сертификата через DNS-01 challenge с Cyon API
    if "$ACME_HOME/acme.sh" --issue --dns dns_cyon -d "$DOMAIN" --email "$EMAIL" --force; then
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

    # Копирование сертификатов из acme.sh
    if "$ACME_HOME/acme.sh" --install-cert -d "$DOMAIN" \
        --cert-file "$TEMP_SSL_DIR/nginx.crt" \
        --key-file "$TEMP_SSL_DIR/nginx.key" \
        --fullchain-file "$TEMP_SSL_DIR/nginx-fullchain.crt" \
        --ca-file "$TEMP_SSL_DIR/nginx-ca.crt"; then

        # Проверка валидности сертификатов
        if openssl x509 -in "$TEMP_SSL_DIR/nginx.crt" -noout -text >/dev/null 2>&1; then
            # Замена старых сертификатов
            cp "$TEMP_SSL_DIR/nginx.crt" "$SSL_DIR/"
            cp "$TEMP_SSL_DIR/nginx.key" "$SSL_DIR/"
            cp "$TEMP_SSL_DIR/nginx-fullchain.crt" "$SSL_DIR/"
            cp "$TEMP_SSL_DIR/nginx-ca.crt" "$SSL_DIR/"

            # Установка правильных прав доступа
            chmod 644 "$SSL_DIR/nginx.crt" "$SSL_DIR/nginx-fullchain.crt" "$SSL_DIR/nginx-ca.crt"
            chmod 600 "$SSL_DIR/nginx.key"

            success "Сертификаты установлены в: $SSL_DIR"
        else
            error "Полученный сертификат невалиден"
        fi
    else
        error "Ошибка установки сертификата"
    fi

    # Очистка временной директории
    rm -rf "$TEMP_SSL_DIR"
}

# Проверка сертификата
verify_certificate() {
    log "Проверка установленного сертификата..."

    if openssl x509 -in "$SSL_DIR/nginx.crt" -text -noout | grep -q "Let's Encrypt"; then
        success "Сертификат Let's Encrypt успешно установлен"

        # Показать информацию о сертификате
        echo ""
        log "Информация о сертификате:"
        openssl x509 -in "$SSL_DIR/nginx.crt" -text -noout | grep -E "(Subject:|Issuer:|Not Before|Not After)"
        echo ""
    else
        error "Сертификат не является сертификатом Let's Encrypt"
    fi
}

# Перезагрузка nginx
reload_nginx() {
    log "Перезагрузка nginx..."

    # Проверка конфигурации nginx
    if docker compose exec nginx nginx -t 2>/dev/null; then
        # Перезагрузка nginx
        if docker compose exec nginx nginx -s reload 2>/dev/null; then
            success "Nginx успешно перезагружен"
        else
            warning "Ошибка перезагрузки nginx, пробуем restart контейнера"
            docker compose restart nginx
        fi
    else
        error "Ошибка в конфигурации nginx"
    fi
}

# Настройка автообновления
setup_auto_renewal() {
    log "Настройка автообновления сертификатов..."

    # acme.sh автоматически создает cron job при установке
    # Проверим, что он существует
    if crontab -l 2>/dev/null | grep -q "acme.sh"; then
        success "Автообновление уже настроено через cron"
    else
        warning "Cron job для автообновления не найден"
        log "Создание cron job для автообновления..."

        # Добавление cron job
        (crontab -l 2>/dev/null; echo "0 2 * * * $ACME_HOME/acme.sh --cron --home $ACME_HOME > /dev/null") | crontab -
        success "Cron job для автообновления создан"
    fi

    # Создание hook скрипта для перезагрузки nginx
    HOOK_SCRIPT="$ACME_HOME/reload-nginx-hook.sh"
    cat > "$HOOK_SCRIPT" << 'EOF'
#!/bin/bash
# Hook script для перезагрузки nginx после обновления сертификата

ERNI_KI_DIR="/home/konstantin/Documents/augment-projects/erni-ki"
cd "$ERNI_KI_DIR"

# Перезагрузка nginx
if docker compose exec nginx nginx -s reload 2>/dev/null; then
    echo "$(date): Nginx reloaded successfully after certificate renewal"
else
    echo "$(date): Failed to reload nginx, restarting container"
    docker compose restart nginx
fi
EOF

    chmod +x "$HOOK_SCRIPT"

    # Обновление acme.sh конфигурации для использования hook
    "$ACME_HOME/acme.sh" --install-cert -d "$DOMAIN" \
        --cert-file "$SSL_DIR/nginx.crt" \
        --key-file "$SSL_DIR/nginx.key" \
        --fullchain-file "$SSL_DIR/nginx-fullchain.crt" \
        --reloadcmd "$HOOK_SCRIPT"

    success "Hook скрипт для автообновления настроен"
}

# Основная функция
main() {
    echo -e "${CYAN}"
    echo "=============================================="
    echo "  ERNI-KI Let's Encrypt SSL Setup"
    echo "  Домен: $DOMAIN"
    echo "=============================================="
    echo -e "${NC}"

    # Проверка, что мы в корне проекта
    if [ ! -f "compose.yml" ] && [ ! -f "compose.yml.example" ]; then
        error "Скрипт должен запускаться из корня проекта ERNI-KI"
    fi

    check_dependencies
    check_cyon_credentials
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
}

# Запуск скрипта
main "$@"
