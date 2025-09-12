#!/bin/bash

# ERNI-KI Let's Encrypt SSL Test с Staging сервером
# Автор: Альтэон Шульц (Tech Lead-Мудрец)
# Версия: 1.0
# Дата: 2025-08-11
# Назначение: Тестирование получения сертификата с staging сервера Let's Encrypt

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
STAGING_DIR="$(pwd)/conf/nginx/ssl-staging"
LOG_FILE="$(pwd)/logs/ssl-staging-test.log"

# Создание директорий
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$STAGING_DIR"

# Проверка Cloudflare API токена
check_cloudflare_credentials() {
    log "Проверка Cloudflare API токена..."

    if [ -z "${CF_Token:-}" ] && [ -z "${CF_Key:-}" ]; then
        error "Cloudflare API токен не найден. Установите переменную CF_Token или CF_Key и CF_Email"
    fi

    if [ -n "${CF_Token:-}" ]; then
        log "Используется Cloudflare API Token"
        # Тест API токена
        if curl -s -H "Authorization: Bearer $CF_Token" \
             -H "Content-Type: application/json" \
             "https://api.cloudflare.com/client/v4/user/tokens/verify" | grep -q '"success":true'; then
            success "Cloudflare API токен действителен"
        else
            error "Cloudflare API токен недействителен"
        fi
    elif [ -n "${CF_Key:-}" ] && [ -n "${CF_Email:-}" ]; then
        log "Используется Cloudflare Global API Key"
        # Тест Global API Key
        if curl -s -H "X-Auth-Email: $CF_Email" \
             -H "X-Auth-Key: $CF_Key" \
             -H "Content-Type: application/json" \
             "https://api.cloudflare.com/client/v4/user" | grep -q '"success":true'; then
            success "Cloudflare Global API Key действителен"
        else
            error "Cloudflare Global API Key недействителен"
        fi
    else
        error "Неполные данные Cloudflare API. Требуется CF_Token или (CF_Key + CF_Email)"
    fi
}

# Получение тестового сертификата
obtain_staging_certificate() {
    log "Получение тестового сертификата с Let's Encrypt Staging сервера..."

    # Установка staging сервера
    "$ACME_HOME/acme.sh" --set-default-ca --server letsencrypt_test

    # Получение сертификата через DNS-01 challenge с Cloudflare API
    if "$ACME_HOME/acme.sh" --issue --dns dns_cf -d "$DOMAIN" --email "$EMAIL" --staging --force; then
        success "Тестовый сертификат успешно получен"
        return 0
    else
        error "Ошибка получения тестового сертификата"
        return 1
    fi
}

# Установка тестового сертификата
install_staging_certificate() {
    log "Установка тестового сертификата..."

    # Установка сертификата в staging директорию
    if "$ACME_HOME/acme.sh" --install-cert -d "$DOMAIN" \
        --cert-file "$STAGING_DIR/nginx.crt" \
        --key-file "$STAGING_DIR/nginx.key" \
        --fullchain-file "$STAGING_DIR/nginx-fullchain.crt" \
        --ca-file "$STAGING_DIR/nginx-ca.crt"; then

        # Установка правильных прав доступа
        chmod 644 "$STAGING_DIR"/*.crt
        chmod 600 "$STAGING_DIR"/*.key

        success "Тестовый сертификат установлен"
    else
        error "Ошибка установки тестового сертификата"
    fi
}

# Проверка тестового сертификата
verify_staging_certificate() {
    log "Проверка тестового сертификата..."

    if [ -f "$STAGING_DIR/nginx.crt" ]; then
        # Проверка срока действия
        local expiry_date=$(openssl x509 -in "$STAGING_DIR/nginx.crt" -noout -enddate | cut -d= -f2)
        log "Тестовый сертификат действителен до: $expiry_date"

        # Проверка домена
        local cert_domain=$(openssl x509 -in "$STAGING_DIR/nginx.crt" -noout -subject | grep -o "CN=[^,]*" | cut -d= -f2)
        if [ "$cert_domain" = "$DOMAIN" ]; then
            success "Тестовый сертификат выдан для правильного домена: $cert_domain"
        else
            warning "Домен в сертификате ($cert_domain) не соответствует ожидаемому ($DOMAIN)"
        fi

        # Проверка издателя (должен быть Fake LE)
        local issuer=$(openssl x509 -in "$STAGING_DIR/nginx.crt" -noout -issuer)
        log "Издатель тестового сертификата: $issuer"

        if echo "$issuer" | grep -q "Fake LE"; then
            success "Сертификат получен с правильного staging сервера"
        else
            warning "Сертификат может быть получен не с staging сервера"
        fi

    else
        error "Файл тестового сертификата не найден: $STAGING_DIR/nginx.crt"
    fi
}

# Очистка тестовых данных
cleanup_staging() {
    log "Очистка тестовых данных..."

    # Удаление staging сертификата из acme.sh
    "$ACME_HOME/acme.sh" --remove -d "$DOMAIN" || true

    # Очистка staging директории
    rm -rf "$STAGING_DIR"

    # Возврат к production серверу
    "$ACME_HOME/acme.sh" --set-default-ca --server letsencrypt

    success "Тестовые данные очищены"
}

# Генерация отчета
generate_test_report() {
    log "Генерация отчета тестирования..."

    local report_file="$(pwd)/logs/ssl-staging-test-report-$(date +%Y%m%d-%H%M%S).txt"

    {
        echo "ERNI-KI Let's Encrypt Staging Test Report"
        echo "Generated: $(date)"
        echo "=========================================="
        echo ""

        echo "Test Configuration:"
        echo "- Domain: $DOMAIN"
        echo "- Email: $EMAIL"
        echo "- Staging Server: Let's Encrypt Staging"
        echo "- Challenge Type: DNS-01 (Cloudflare)"
        echo ""

        echo "API Credentials Test:"
        if [ -n "${CF_Token:-}" ]; then
            echo "- Type: Cloudflare API Token"
            echo "- Status: Configured"
        elif [ -n "${CF_Key:-}" ] && [ -n "${CF_Email:-}" ]; then
            echo "- Type: Cloudflare Global API Key"
            echo "- Status: Configured"
        else
            echo "- Status: NOT CONFIGURED"
        fi
        echo ""

        echo "Certificate Information:"
        if [ -f "$STAGING_DIR/nginx.crt" ]; then
            openssl x509 -in "$STAGING_DIR/nginx.crt" -noout -subject -issuer -dates 2>/dev/null || echo "Error reading certificate"
        else
            echo "No staging certificate found"
        fi
        echo ""

        echo "Next Steps:"
        echo "1. If test successful, run production script:"
        echo "   ./scripts/ssl/setup-letsencrypt-cloudflare.sh"
        echo "2. Monitor certificate installation"
        echo "3. Test HTTPS access to $DOMAIN"
        echo ""

    } > "$report_file"

    success "Отчет сохранен: $report_file"
    cat "$report_file"
}

# Основная функция
main() {
    echo -e "${CYAN}"
    echo "=================================================="
    echo "  ERNI-KI Let's Encrypt Staging Test"
    echo "  Тестирование с безопасным staging сервером"
    echo "=================================================="
    echo -e "${NC}"

    # Проверка аргументов
    local action="${1:-test}"

    case "$action" in
        "test")
            check_cloudflare_credentials
            obtain_staging_certificate
            install_staging_certificate
            verify_staging_certificate
            generate_test_report
            cleanup_staging
            ;;
        "cleanup")
            cleanup_staging
            ;;
        *)
            echo "Использование: $0 [test|cleanup]"
            echo "  test    - Полное тестирование (по умолчанию)"
            echo "  cleanup - Очистка тестовых данных"
            exit 1
            ;;
    esac

    echo ""
    success "🧪 Тестирование Let's Encrypt завершено!"
    echo ""
    log "Если тест прошел успешно, запустите production скрипт:"
    echo "  ./scripts/ssl/setup-letsencrypt-cloudflare.sh"
    echo ""
    log "Логи тестирования: $LOG_FILE"
}

# Запуск скрипта
main "$@" 2>&1 | tee -a "$LOG_FILE"
