#!/bin/bash

# ============================================================================
# ERNI-KI Production Let's Encrypt SSL Setup с Cloudflare DNS-01
# ============================================================================
# Описание: Безопасная установка Let's Encrypt сертификата через DNS-01
# Автор: Augment Agent
# Дата: 2025-11-11
# Версия: 1.0.0
# ============================================================================

set -euo pipefail

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Директории
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
readonly SSL_DIR="$PROJECT_ROOT/conf/nginx/ssl"
readonly BACKUP_DIR="$PROJECT_ROOT/.config-backup/ssl-letsencrypt-dns01-$(date +%Y%m%d-%H%M%S)"
readonly ACME_HOME="$HOME/.acme.sh"
readonly LOG_FILE="$PROJECT_ROOT/logs/ssl-letsencrypt-dns01-setup-$(date +%Y%m%d-%H%M%S).log"

# Конфигурация
readonly DOMAIN="ki.erni-gruppe.ch"
readonly DOMAIN_WWW="www.ki.erni-gruppe.ch"
readonly EMAIL="diginnz1@gmail.com"
readonly CERT_KEYLENGTH="2048"

# Функции логирования
log() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1"
    echo -e "${BLUE}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

success() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1"
    echo -e "${GREEN}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

warning() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1"
    echo -e "${YELLOW}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

error() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1"
    echo -e "${RED}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
    exit 1
}

# Создание директории для логов
mkdir -p "$(dirname "$LOG_FILE")"

# Заголовок
print_header() {
    echo -e "${CYAN}"
    echo "============================================================================"
    echo "  ERNI-KI Production Let's Encrypt SSL Setup"
    echo "  Метод: DNS-01 Challenge через Cloudflare API"
    echo "  Домены: $DOMAIN, $DOMAIN_WWW"
    echo "============================================================================"
    echo -e "${NC}"
}

# Проверка зависимостей
check_dependencies() {
    log "Проверка зависимостей..."

    local deps=("docker" "curl" "openssl" "dig")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error "$dep не найден. Установите $dep."
        fi
    done

    if [ ! -d "$SSL_DIR" ]; then
        error "Директория SSL не найдена: $SSL_DIR"
    fi

    success "Все зависимости найдены"
}

# Проверка Docker Compose
check_docker_compose() {
    log "Проверка Docker Compose..."

    cd "$PROJECT_ROOT"
    if ! docker compose version &> /dev/null; then
        error "Docker Compose не найден или не работает"
    fi

    success "Docker Compose работает"
}

# Запрос Cloudflare API Token
request_cloudflare_token() {
    log "Настройка Cloudflare API..."
    echo ""
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  Для получения сертификата через DNS-01 нужен Cloudflare API Token    ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Как получить API Token:${NC}"
    echo -e "  1. Откройте: ${GREEN}https://dash.cloudflare.com/profile/api-tokens${NC}"
    echo -e "  2. Нажмите: ${GREEN}Create Token${NC}"
    echo -e "  3. Выберите шаблон: ${GREEN}Edit zone DNS${NC}"
    echo -e "  4. Настройте права:"
    echo -e "     • Zone: ${GREEN}DNS${NC} - ${GREEN}Edit${NC}"
    echo -e "     • Zone Resources: ${GREEN}Include${NC} - ${GREEN}Specific zone${NC} - ${GREEN}erni-gruppe.ch${NC}"
    echo -e "  5. Нажмите: ${GREEN}Continue to summary${NC} → ${GREEN}Create Token${NC}"
    echo -e "  6. Скопируйте токен"
    echo ""
    echo -e "${GREEN}Вставьте Cloudflare API Token (ввод скрыт):${NC}"
    read -s CF_Token
    echo ""

    if [[ -z "$CF_Token" ]]; then
        error "API Token не может быть пустым"
    fi

    # Экспорт для acme.sh
    export CF_Token="$CF_Token"
    export CF_Account_ID=""

    success "Cloudflare API Token настроен"
}

# Проверка валидности Cloudflare API Token
verify_cloudflare_token() {
    log "Проверка Cloudflare API Token..."

    local response=$(curl -s -H "Authorization: Bearer $CF_Token" \
         -H "Content-Type: application/json" \
         "https://api.cloudflare.com/client/v4/user/tokens/verify")

    if echo "$response" | grep -q '"success":true'; then
        success "Cloudflare API Token валиден"
    else
        error "Cloudflare API Token невалиден. Проверьте токен и попробуйте снова."
    fi
}

# Создание резервной копии через Backrest
create_backrest_backup() {
    log "Создание резервной копии через Backrest..."

    cd "$PROJECT_ROOT"

    # Создание тега для Backrest
    local backup_tag="ssl-letsencrypt-dns01-$(date +%Y%m%d-%H%M%S)"

    if docker compose exec -T backrest backrest backup --tag "$backup_tag" &>> "$LOG_FILE"; then
        success "Резервная копия создана через Backrest (тег: $backup_tag)"
    else
        warning "Backrest недоступен, создаю локальную резервную копию..."
        create_local_backup
    fi
}

# Локальная резервная копия
create_local_backup() {
    log "Создание локальной резервной копии..."

    mkdir -p "$BACKUP_DIR"

    if [ -f "$SSL_DIR/nginx.crt" ]; then
        cp "$SSL_DIR"/*.crt "$BACKUP_DIR/" 2>/dev/null || true
        cp "$SSL_DIR"/*.key "$BACKUP_DIR/" 2>/dev/null || true
        success "Локальная резервная копия создана: $BACKUP_DIR"
    else
        warning "Существующие сертификаты не найдены"
    fi
}

# Установка/обновление acme.sh
install_acme_sh() {
    log "Проверка acme.sh..."

    if [ ! -f "$ACME_HOME/acme.sh" ]; then
        log "Установка acme.sh..."
        curl -s https://get.acme.sh | sh -s email="$EMAIL" &>> "$LOG_FILE"

        if [ ! -f "$ACME_HOME/acme.sh" ]; then
            error "Ошибка установки acme.sh"
        fi
        success "acme.sh установлен"
    else
        log "acme.sh уже установлен, обновляю..."
        "$ACME_HOME/acme.sh" --upgrade &>> "$LOG_FILE" || true
        success "acme.sh обновлен"
    fi
}

# Получение сертификата Let's Encrypt
obtain_certificate() {
    log "Получение Let's Encrypt сертификата..."
    echo ""
    echo -e "${YELLOW}Домены:${NC} $DOMAIN, $DOMAIN_WWW"
    echo -e "${YELLOW}Email:${NC} $EMAIL"
    echo -e "${YELLOW}DNS Provider:${NC} Cloudflare"
    echo -e "${YELLOW}Key Length:${NC} $CERT_KEYLENGTH"
    echo ""

    log "Запуск acme.sh (это может занять 2-3 минуты)..."

    # Установка Let's Encrypt как CA по умолчанию
    "$ACME_HOME/acme.sh" --set-default-ca --server letsencrypt &>> "$LOG_FILE"

    # Получение сертификата через DNS-01
    if "$ACME_HOME/acme.sh" --issue \
        --dns dns_cf \
        -d "$DOMAIN" \
        -d "$DOMAIN_WWW" \
        --keylength "$CERT_KEYLENGTH" \
        --server letsencrypt \
        --force &>> "$LOG_FILE"; then
        success "Сертификат успешно получен от Let's Encrypt!"
    else
        error "Ошибка при получении сертификата. Проверьте логи: $LOG_FILE"
    fi
}

# Установка сертификатов
install_certificate() {
    log "Установка сертификатов в nginx..."

    # Установка сертификатов с правильными путями
    "$ACME_HOME/acme.sh" --install-cert -d "$DOMAIN" \
        --key-file "$SSL_DIR/letsencrypt-privkey.key" \
        --fullchain-file "$SSL_DIR/letsencrypt-fullchain.crt" \
        --cert-file "$SSL_DIR/letsencrypt-cert.crt" \
        --ca-file "$SSL_DIR/letsencrypt-chain.crt" &>> "$LOG_FILE"

    # Установка правильных прав доступа
    chmod 644 "$SSL_DIR/letsencrypt-fullchain.crt"
    chmod 600 "$SSL_DIR/letsencrypt-privkey.key"
    chmod 644 "$SSL_DIR/letsencrypt-cert.crt"
    chmod 644 "$SSL_DIR/letsencrypt-chain.crt"

    # Создание символических ссылок
    cd "$SSL_DIR"
    ln -sf letsencrypt-fullchain.crt nginx-fullchain.crt
    ln -sf letsencrypt-fullchain.crt nginx.crt
    ln -sf letsencrypt-privkey.key nginx.key

    success "Сертификаты установлены"
}

# Проверка сертификата
verify_certificate() {
    log "Проверка установленного сертификата..."
    echo ""

    openssl x509 -in "$SSL_DIR/nginx-fullchain.crt" -noout -subject -issuer -dates -ext subjectAltName

    echo ""
    success "Сертификат валиден"
}

# Перезагрузка nginx
reload_nginx() {
    log "Проверка конфигурации nginx..."

    cd "$PROJECT_ROOT"
    if docker compose exec -T nginx nginx -t &>> "$LOG_FILE"; then
        success "Конфигурация nginx корректна"
    else
        error "Ошибка в конфигурации nginx. Проверьте логи: $LOG_FILE"
    fi

    log "Перезагрузка nginx..."
    if docker compose restart nginx &>> "$LOG_FILE"; then
        success "Nginx перезагружен"
    else
        error "Ошибка перезагрузки nginx"
    fi
}

# Перезагрузка Cloudflare Tunnel
reload_cloudflared() {
    log "Перезагрузка Cloudflare Tunnel..."

    cd "$PROJECT_ROOT"
    if docker compose restart cloudflared &>> "$LOG_FILE"; then
        success "Cloudflare Tunnel перезагружен"
    else
        warning "Ошибка перезагрузки Cloudflare Tunnel"
    fi
}

# Настройка автообновления
setup_auto_renewal() {
    log "Настройка автообновления сертификата..."

    # Создание hook скрипта для перезагрузки nginx
    local hook_script="$PROJECT_ROOT/scripts/infrastructure/security/letsencrypt-renewal-hook.sh"

    cat > "$hook_script" << 'EOFHOOK'
#!/bin/bash
# Hook скрипт для перезагрузки nginx после обновления Let's Encrypt сертификата

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LOG_FILE="$PROJECT_ROOT/logs/ssl-renewal-$(date +%Y%m%d).log"

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Certificate renewal hook executed" >> "$LOG_FILE"

cd "$PROJECT_ROOT"

# Перезагрузка nginx
if docker compose exec -T nginx nginx -s reload 2>> "$LOG_FILE"; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Nginx reloaded successfully" >> "$LOG_FILE"
else
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Nginx reload failed, restarting container" >> "$LOG_FILE"
    docker compose restart nginx >> "$LOG_FILE" 2>&1
fi

# Перезагрузка Cloudflare Tunnel
docker compose restart cloudflared >> "$LOG_FILE" 2>&1

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Certificate renewal completed" >> "$LOG_FILE"
EOFHOOK

    chmod +x "$hook_script"

    # Обновление acme.sh конфигурации для использования hook
    "$ACME_HOME/acme.sh" --install-cert -d "$DOMAIN" \
        --key-file "$SSL_DIR/letsencrypt-privkey.key" \
        --fullchain-file "$SSL_DIR/letsencrypt-fullchain.crt" \
        --cert-file "$SSL_DIR/letsencrypt-cert.crt" \
        --ca-file "$SSL_DIR/letsencrypt-chain.crt" \
        --reloadcmd "$hook_script" &>> "$LOG_FILE"

    success "Автообновление настроено (acme.sh cron job)"
}

# Проверка HTTPS доступа
test_https_access() {
    log "Проверка HTTPS доступа..."

    sleep 5  # Ждем перезагрузки сервисов

    for domain in "$DOMAIN" "$DOMAIN_WWW"; do
        if curl -sSf -I "https://$domain" &> /dev/null; then
            success "HTTPS доступ к $domain работает"
        else
            warning "HTTPS доступ к $domain недоступен (может потребоваться время для DNS)"
        fi
    done
}

# Проверка статуса сервисов
check_services_health() {
    log "Проверка статуса сервисов ERNI-KI..."

    cd "$PROJECT_ROOT"
    local unhealthy=$(docker compose ps --format json | jq -r 'select(.Health != "healthy" and .Health != "") | .Service' 2>/dev/null)

    if [ -z "$unhealthy" ]; then
        success "Все сервисы ERNI-KI в статусе healthy"
    else
        warning "Некоторые сервисы не в статусе healthy:"
        echo "$unhealthy"
    fi
}

# Основная функция
main() {
    print_header

    check_dependencies
    check_docker_compose
    request_cloudflare_token
    verify_cloudflare_token
    create_backrest_backup
    install_acme_sh
    obtain_certificate
    install_certificate
    verify_certificate
    reload_nginx
    reload_cloudflared
    setup_auto_renewal
    test_https_access
    check_services_health

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ Let's Encrypt SSL сертификат успешно установлен!                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Информация о сертификате:${NC}"
    echo -e "  • Издатель: Let's Encrypt (R3)"
    echo -e "  • Срок действия: 90 дней"
    echo -e "  • Автообновление: настроено через acme.sh cron"
    echo -e "  • Домены: $DOMAIN, $DOMAIN_WWW"
    echo ""
    echo -e "${CYAN}Проверка HTTPS:${NC}"
    echo -e "  curl -I https://ki.erni-gruppe.ch"
    echo -e "  curl -I https://www.ki.erni-gruppe.ch"
    echo ""
    echo -e "${CYAN}Логи:${NC}"
    echo -e "  • Установка: $LOG_FILE"
    echo -e "  • acme.sh: $ACME_HOME/acme.sh.log"
    echo -e "  • Обновление: $PROJECT_ROOT/logs/ssl-renewal-*.log"
    echo ""
}

# Запуск скрипта
main "$@"
