#!/bin/bash

# ERNI-KI Self-Signed Certificate Renewal Script
# Обновление самоподписанного SSL сертификата для ki.erni-gruppe.ch

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
SSL_DIR="$(pwd)/conf/nginx/ssl"
BACKUP_DIR="$(pwd)/.config-backup/ssl-renewal-$(date +%Y%m%d-%H%M%S)"
CERT_VALIDITY_DAYS=730  # 2 года
KEY_SIZE=4096

# Проверка окружения
check_environment() {
    log "Проверка окружения..."

    # Проверка, что мы в корне проекта
    if [ ! -f "compose.yml" ] && [ ! -f "compose.yml.example" ]; then
        error "Скрипт должен запускаться из корня проекта ERNI-KI"
    fi

    # Проверка директории SSL
    if [ ! -d "$SSL_DIR" ]; then
        error "Директория SSL не найдена: $SSL_DIR"
    fi

    # Проверка наличия openssl
    if ! command -v openssl >/dev/null 2>&1; then
        error "OpenSSL не найден. Установите openssl"
    fi

    success "Окружение проверено"
}

# Создание резервной копии
create_backup() {
    log "Создание резервной копии текущих сертификатов..."

    mkdir -p "$BACKUP_DIR"

    if [ -f "$SSL_DIR/nginx.crt" ]; then
        cp "$SSL_DIR/nginx.crt" "$BACKUP_DIR/"
        cp "$SSL_DIR/nginx.key" "$BACKUP_DIR/"

        # Копирование дополнительных файлов если есть
        [ -f "$SSL_DIR/nginx-fullchain.crt" ] && cp "$SSL_DIR/nginx-fullchain.crt" "$BACKUP_DIR/"
        [ -f "$SSL_DIR/nginx-ca.crt" ] && cp "$SSL_DIR/nginx-ca.crt" "$BACKUP_DIR/"

        log "Резервная копия создана в: $BACKUP_DIR"

        # Показать информацию о старом сертификате
        echo ""
        log "Информация о текущем сертификате:"
        openssl x509 -in "$SSL_DIR/nginx.crt" -noout -subject -issuer -dates
        echo ""
    else
        warning "Текущие сертификаты не найдены"
    fi
}

# Генерация нового сертификата
generate_certificate() {
    log "Генерация нового самоподписанного сертификата..."

    # Создание временной директории
    TEMP_DIR="/tmp/ssl-gen-$$"
    mkdir -p "$TEMP_DIR"

    # Создание конфигурационного файла для расширений
    cat > "$TEMP_DIR/cert.conf" << EOF
[req]
default_bits = $KEY_SIZE
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=CH
ST=Zurich
L=Zurich
O=ERNI-KI
OU=IT Department
CN=$DOMAIN

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = localhost
IP.1 = 127.0.0.1
IP.2 = 192.168.62.140
EOF

    # Генерация приватного ключа
    log "Генерация приватного ключа ($KEY_SIZE бит)..."
    openssl genrsa -out "$TEMP_DIR/nginx.key" $KEY_SIZE

    # Генерация сертификата
    log "Генерация сертификата (действителен $CERT_VALIDITY_DAYS дней)..."
    openssl req -new -x509 -key "$TEMP_DIR/nginx.key" \
        -out "$TEMP_DIR/nginx.crt" \
        -days $CERT_VALIDITY_DAYS \
        -config "$TEMP_DIR/cert.conf" \
        -extensions v3_req

    # Проверка сгенерированного сертификата
    if openssl x509 -in "$TEMP_DIR/nginx.crt" -noout -text >/dev/null 2>&1; then
        success "Сертификат успешно сгенерирован"
    else
        error "Ошибка генерации сертификата"
    fi

    # Установка сертификатов
    log "Установка новых сертификатов..."
    cp "$TEMP_DIR/nginx.crt" "$SSL_DIR/"
    cp "$TEMP_DIR/nginx.key" "$SSL_DIR/"

    # Создание fullchain (для совместимости)
    cp "$SSL_DIR/nginx.crt" "$SSL_DIR/nginx-fullchain.crt"
    cp "$SSL_DIR/nginx.crt" "$SSL_DIR/nginx-ca.crt"

    # Установка правильных прав доступа
    chmod 644 "$SSL_DIR/nginx.crt" "$SSL_DIR/nginx-fullchain.crt" "$SSL_DIR/nginx-ca.crt"
    chmod 600 "$SSL_DIR/nginx.key"

    # Очистка временной директории
    rm -rf "$TEMP_DIR"

    success "Новые сертификаты установлены"
}

# Проверка нового сертификата
verify_certificate() {
    log "Проверка нового сертификата..."

    if openssl x509 -in "$SSL_DIR/nginx.crt" -noout -text >/dev/null 2>&1; then
        success "Новый сертификат валиден"

        # Показать информацию о новом сертификате
        echo ""
        log "Информация о новом сертификате:"
        openssl x509 -in "$SSL_DIR/nginx.crt" -noout -subject -issuer -dates
        echo ""

        # Проверка SAN (Subject Alternative Names)
        log "Subject Alternative Names:"
        openssl x509 -in "$SSL_DIR/nginx.crt" -noout -text | grep -A 3 "Subject Alternative Name" || echo "SAN не найдены"
        echo ""
    else
        error "Новый сертификат невалиден"
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
            if docker compose restart nginx; then
                success "Nginx контейнер перезапущен"
            else
                error "Ошибка перезапуска nginx контейнера"
            fi
        fi
    else
        error "Ошибка в конфигурации nginx"
    fi
}

# Тестирование HTTPS
test_https() {
    log "Тестирование HTTPS доступности..."

    # Ожидание запуска nginx
    sleep 5

    # Тест локального доступа
    if curl -k -I "https://localhost:443/" --connect-timeout 10 >/dev/null 2>&1; then
        success "Локальный HTTPS доступен"
    else
        warning "Локальный HTTPS недоступен"
    fi

    # Тест доступа через домен
    if curl -k -I "https://$DOMAIN/" --connect-timeout 10 >/dev/null 2>&1; then
        success "HTTPS через домен доступен"

        # Показать заголовки ответа
        echo ""
        log "HTTP заголовки ответа:"
        curl -k -I "https://$DOMAIN/" --connect-timeout 10 2>/dev/null | head -5
        echo ""
    else
        warning "HTTPS через домен недоступен"
    fi
}

# Обновление мониторинга
update_monitoring() {
    log "Обновление конфигурации мониторинга..."

    # Обновление конфигурации мониторинга
    if [ -f "conf/ssl/monitoring.conf" ]; then
        # Добавление записи о обновлении
        echo "# Сертификат обновлен: $(date)" >> conf/ssl/monitoring.conf
        log "Конфигурация мониторинга обновлена"
    fi

    # Запуск проверки мониторинга
    if [ -x "scripts/ssl/monitor-certificates.sh" ]; then
        log "Запуск проверки мониторинга..."
        ./scripts/ssl/monitor-certificates.sh check || warning "Ошибка проверки мониторинга"
    fi
}

# Генерация отчета
generate_report() {
    local report_file="logs/ssl-renewal-report-$(date +%Y%m%d-%H%M%S).txt"
    mkdir -p "$(dirname "$report_file")"

    {
        echo "ERNI-KI SSL Certificate Renewal Report"
        echo "Generated: $(date)"
        echo "========================================"
        echo ""

        echo "Certificate Information:"
        openssl x509 -in "$SSL_DIR/nginx.crt" -noout -subject -issuer -dates 2>/dev/null || echo "Error reading certificate"
        echo ""

        echo "Backup Location:"
        echo "$BACKUP_DIR"
        echo ""

        echo "HTTPS Test Results:"
        if curl -k -I "https://$DOMAIN/" --connect-timeout 5 >/dev/null 2>&1; then
            echo "✓ HTTPS accessible"
        else
            echo "✗ HTTPS not accessible"
        fi
        echo ""

        echo "Next Renewal Date:"
        echo "$(date -d "+$((CERT_VALIDITY_DAYS - 30)) days" '+%Y-%m-%d') (30 days before expiration)"

    } > "$report_file"

    log "Отчет сохранен: $report_file"
}

# Основная функция
main() {
    echo -e "${CYAN}"
    echo "=============================================="
    echo "  ERNI-KI Self-Signed Certificate Renewal"
    echo "  Domain: $DOMAIN"
    echo "  Validity: $CERT_VALIDITY_DAYS days"
    echo "=============================================="
    echo -e "${NC}"

    check_environment
    create_backup
    generate_certificate
    verify_certificate
    reload_nginx
    test_https
    update_monitoring
    generate_report

    echo ""
    success "🎉 SSL сертификат успешно обновлен!"
    echo ""
    log "Следующие шаги:"
    echo "1. Проверьте HTTPS доступ: https://$DOMAIN"
    echo "2. Добавьте исключение в браузере для самоподписанного сертификата"
    echo "3. Следующее обновление рекомендуется через $((CERT_VALIDITY_DAYS - 30)) дней"
    echo ""
    log "Резервная копия старых сертификатов: $BACKUP_DIR"
}

# Запуск скрипта
main "$@"
