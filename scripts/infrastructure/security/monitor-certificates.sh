#!/bin/bash

# ERNI-KI SSL Certificate Monitoring Script
# Мониторинг срока действия SSL сертификатов и автоматическое обновление

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
}

# Конфигурация
DOMAIN="ki.erni-gruppe.ch"
SSL_DIR="$(pwd)/conf/nginx/ssl"
CERT_FILE="$SSL_DIR/nginx.crt"
FULLCHAIN_FILE="$SSL_DIR/nginx-fullchain.crt"
DAYS_WARNING=30
DAYS_CRITICAL=7
LOG_FILE="$(pwd)/logs/ssl-monitor.log"
WEBHOOK_URL="${SSL_WEBHOOK_URL:-}"

# Создание директории для логов
mkdir -p "$(dirname "$LOG_FILE")"

# Функция для отправки уведомлений
send_notification() {
    local message="$1"
    local level="${2:-info}"

    # Логирование
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"

    # Webhook уведомление (если настроен)
    if [ -n "$WEBHOOK_URL" ]; then
        curl -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"ERNI-KI SSL Monitor: $message\", \"level\":\"$level\"}" \
            >/dev/null 2>&1 || true
    fi

    # Системное уведомление
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "ERNI-KI SSL Monitor" "$message" >/dev/null 2>&1 || true
    fi
}

# Проверка срока действия сертификата
check_certificate_expiry() {
    log "Проверка срока действия сертификата..."

    local cert_to_check="$CERT_FILE"

    # Используем fullchain если доступен (для Let's Encrypt)
    if [ -f "$FULLCHAIN_FILE" ]; then
        cert_to_check="$FULLCHAIN_FILE"
    fi

    if [ ! -f "$cert_to_check" ]; then
        error "Сертификат не найден: $cert_to_check"
        send_notification "SSL сертификат не найден: $cert_to_check" "error"
        return 1
    fi

    # Получение даты истечения
    local expiry_date
    if ! expiry_date=$(openssl x509 -in "$cert_to_check" -noout -enddate 2>/dev/null | cut -d= -f2); then
        error "Не удалось прочитать дату истечения сертификата"
        send_notification "Ошибка чтения SSL сертификата" "error"
        return 1
    fi

    # Вычисление дней до истечения
    local expiry_timestamp current_timestamp days_left
    expiry_timestamp=$(date -d "$expiry_date" +%s)
    current_timestamp=$(date +%s)
    days_left=$(( (expiry_timestamp - current_timestamp) / 86400 ))

    log "Сертификат действителен до: $expiry_date"
    log "Дней до истечения: $days_left"

    # Проверка критических сроков
    if [ $days_left -lt 0 ]; then
        error "Сертификат истек $((days_left * -1)) дней назад!"
        send_notification "SSL сертификат истек $((days_left * -1)) дней назад!" "critical"
        return 2
    elif [ $days_left -lt $DAYS_CRITICAL ]; then
        error "КРИТИЧНО: Сертификат истекает через $days_left дней!"
        send_notification "КРИТИЧНО: SSL сертификат истекает через $days_left дней!" "critical"
        return 2
    elif [ $days_left -lt $DAYS_WARNING ]; then
        warning "ВНИМАНИЕ: Сертификат истекает через $days_left дней"
        send_notification "ВНИМАНИЕ: SSL сертификат истекает через $days_left дней" "warning"
        return 1
    else
        success "Сертификат действителен еще $days_left дней"
        return 0
    fi
}

# Проверка типа сертификата
check_certificate_type() {
    log "Проверка типа сертификата..."

    if [ ! -f "$CERT_FILE" ]; then
        warning "Сертификат не найден"
        return 1
    fi

    local issuer
    issuer=$(openssl x509 -in "$CERT_FILE" -noout -issuer 2>/dev/null | cut -d= -f2-)

    if echo "$issuer" | grep -qi "let's encrypt"; then
        success "Используется сертификат Let's Encrypt"
        return 0
    elif echo "$issuer" | grep -qi "erni-ki"; then
        warning "Используется самоподписанный сертификат"
        return 1
    else
        log "Используется сертификат от: $issuer"
        return 0
    fi
}

# Автоматическое обновление самоподписанного сертификата
auto_renew_certificate() {
    log "Попытка автоматического обновления самоподписанного сертификата..."

    # Проверка наличия скрипта обновления
    local renewal_script="$(pwd)/scripts/ssl/renew-self-signed.sh"
    if [ ! -f "$renewal_script" ]; then
        error "Скрипт обновления не найден: $renewal_script"
        send_notification "Скрипт обновления самоподписанного сертификата не найден" "error"
        return 1
    fi

    # Попытка обновления
    log "Запуск обновления самоподписанного сертификата..."
    if "$renewal_script"; then
        success "Самоподписанный сертификат успешно обновлен"
        send_notification "Самоподписанный SSL сертификат успешно обновлен" "success"
        return 0
    else
        error "Ошибка обновления самоподписанного сертификата"
        send_notification "Ошибка автоматического обновления самоподписанного SSL сертификата" "error"
        return 1
    fi
}

# Перезагрузка nginx
reload_nginx() {
    log "Перезагрузка nginx после обновления сертификата..."

    # Проверка конфигурации nginx
    if docker compose exec nginx nginx -t 2>/dev/null; then
        # Перезагрузка nginx
        if docker compose exec nginx nginx -s reload 2>/dev/null; then
            success "Nginx успешно перезагружен"
            send_notification "Nginx перезагружен после обновления SSL сертификата" "info"
        else
            warning "Ошибка перезагрузки nginx, пробуем restart контейнера"
            if docker compose restart nginx; then
                success "Nginx контейнер перезапущен"
                send_notification "Nginx контейнер перезапущен после обновления SSL" "info"
            else
                error "Ошибка перезапуска nginx контейнера"
                send_notification "Ошибка перезапуска nginx после обновления SSL" "error"
                return 1
            fi
        fi
    else
        error "Ошибка в конфигурации nginx"
        send_notification "Ошибка в конфигурации nginx после обновления SSL" "error"
        return 1
    fi
}

# Проверка доступности HTTPS
test_https_connectivity() {
    log "Проверка HTTPS доступности..."

    # Проверка локального доступа
    if curl -k -I "https://localhost:443/" --connect-timeout 5 >/dev/null 2>&1; then
        success "Локальный HTTPS доступен"
    else
        warning "Локальный HTTPS недоступен"
        send_notification "Локальный HTTPS недоступен" "warning"
        attempt_nginx_recovery "local"
    fi

    # Проверка доступа через домен
    if curl -k -I "https://$DOMAIN/health" --resolve "$DOMAIN:443:127.0.0.1" --connect-timeout 5 >/dev/null 2>&1 \
       || curl -k -I "https://$DOMAIN/" --connect-timeout 8 >/dev/null 2>&1; then
        success "HTTPS через домен доступен"
    else
        warning "HTTPS через домен недоступен"
        send_notification "HTTPS через домен $DOMAIN недоступен" "warning"
        attempt_nginx_recovery "domain"
    fi
}

attempt_nginx_recovery() {
    local scope="${1:-local}"
    if ! command -v docker >/dev/null 2>&1; then
        warning "Docker не доступен, пропускаю восстановление Nginx ($scope)"
        return
    fi

    log "Попытка восстановить Nginx (${scope} scope)..."
    if docker compose ps nginx >/dev/null 2>&1; then
        if docker compose exec -T nginx nginx -t >/dev/null 2>&1; then
            docker compose exec -T nginx nginx -s reload >/dev/null 2>&1 \
              && success "Nginx перезагружен после ошибки HTTPS (${scope})" \
              || docker compose restart nginx >/dev/null 2>&1
        else
            warning "nginx -t вернул ошибку, выполняю docker compose restart nginx"
            docker compose restart nginx >/dev/null 2>&1 || warning "Не удалось перезапустить nginx автоматически"
        fi
    else
        warning "Контейнер nginx не найден (docker compose ps nginx)"
    fi
}

# Генерация отчета
generate_report() {
    local report_file="$(pwd)/logs/ssl-report-$(date +%Y%m%d-%H%M%S).txt"

    {
        echo "ERNI-KI SSL Certificate Report"
        echo "Generated: $(date)"
        echo "================================"
        echo ""

        echo "Certificate Information:"
        if [ -f "$CERT_FILE" ]; then
            openssl x509 -in "$CERT_FILE" -noout -subject -issuer -dates 2>/dev/null || echo "Error reading certificate"
        else
            echo "Certificate not found: $CERT_FILE"
        fi
        echo ""

        echo "HTTPS Connectivity:"
        if curl -k -I "https://$DOMAIN/" --connect-timeout 5 >/dev/null 2>&1; then
            echo "✓ HTTPS accessible"
        else
            echo "✗ HTTPS not accessible"
        fi
        echo ""

        echo "SSL Configuration:"
        if echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" >/dev/null 2>&1; then
            echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null | grep -E "(Protocol|Cipher|Verify)" || echo "SSL connection failed"
        else
            echo "✗ SSL connection failed"
        fi

    } > "$report_file"

    log "Отчет сохранен: $report_file"
}

# Основная функция
main() {
    local action="${1:-check}"

    echo -e "${CYAN}"
    echo "=============================================="
    echo "  ERNI-KI SSL Certificate Monitor"
    echo "  Domain: $DOMAIN"
    echo "  Action: $action"
    echo "=============================================="
    echo -e "${NC}"

    # Проверка, что мы в корне проекта
    if [ ! -f "compose.yml" ] && [ ! -f "compose.yml.example" ]; then
        error "Скрипт должен запускаться из корня проекта ERNI-KI"
        exit 1
    fi

    case "$action" in
        "check")
            check_certificate_type
            local cert_status
            check_certificate_expiry
            cert_status=$?
            test_https_connectivity

            if [ $cert_status -eq 2 ]; then
                # Критическое состояние - попытка автообновления
                auto_renew_certificate
            fi
            ;;
        "renew")
            auto_renew_certificate
            ;;
        "report")
            generate_report
            ;;
        "test")
            test_https_connectivity
            ;;
        *)
            echo "Использование: $0 [check|renew|report|test]"
            echo "  check  - Проверка срока действия сертификата (по умолчанию)"
            echo "  renew  - Принудительное обновление сертификата"
            echo "  report - Генерация подробного отчета"
            echo "  test   - Тестирование HTTPS доступности"
            exit 1
            ;;
    esac

    success "Мониторинг завершен"
}

# Запуск скрипта
main "$@"
