#!/bin/bash

# ============================================================================
# Скрипт создания Let's Encrypt сертификатов через DNS-01 challenge
# ============================================================================
# Описание: Получение SSL сертификатов через Cloudflare DNS API
# Автор: Augment Agent
# Дата: 11.11.2025
# ============================================================================

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Директории
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SSL_DIR="$PROJECT_ROOT/conf/nginx/ssl"
BACKUP_DIR="$PROJECT_ROOT/.config-backup/ssl-$(date +%Y%m%d-%H%M%S)"
ACME_HOME="$HOME/.acme.sh"

# Домены
DOMAIN="ki.erni-gruppe.ch"
DOMAIN_WWW="www.ki.erni-gruppe.ch"
EMAIL="diginnz1@gmail.com"

echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}Создание Let's Encrypt сертификатов через Cloudflare DNS${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""

# Проверка/установка acme.sh
if [[ ! -f "$ACME_HOME/acme.sh" ]]; then
    echo -e "${YELLOW}⚠️  acme.sh не установлен. Устанавливаю...${NC}"
    curl https://get.acme.sh | sh -s email=$EMAIL
    echo -e "${GREEN}✅ acme.sh установлен${NC}"
    # Перезагрузка переменных окружения
    source "$HOME/.acme.sh/acme.sh.env"
else
    echo -e "${GREEN}✅ acme.sh уже установлен${NC}"
fi
echo ""

# Запрос Cloudflare API Token
echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}Настройка Cloudflare API${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""
echo -e "${YELLOW}Для получения сертификата через DNS-01 challenge нужен Cloudflare API Token${NC}"
echo ""
echo -e "${YELLOW}Как получить API Token:${NC}"
echo -e "1. Откройте: ${GREEN}https://dash.cloudflare.com/profile/api-tokens${NC}"
echo -e "2. Нажмите: ${GREEN}Create Token${NC}"
echo -e "3. Выберите шаблон: ${GREEN}Edit zone DNS${NC}"
echo -e "4. Настройте права:"
echo -e "   - Zone: ${GREEN}DNS${NC} - ${GREEN}Edit${NC}"
echo -e "   - Zone Resources: ${GREEN}Include${NC} - ${GREEN}Specific zone${NC} - ${GREEN}erni-gruppe.ch${NC}"
echo -e "5. Нажмите: ${GREEN}Continue to summary${NC} → ${GREEN}Create Token${NC}"
echo -e "6. Скопируйте токен"
echo ""
echo -e "${GREEN}Вставьте Cloudflare API Token:${NC}"
read -s CF_Token
echo ""

if [[ -z "$CF_Token" ]]; then
    echo -e "${RED}❌ Ошибка: API Token не может быть пустым${NC}"
    exit 1
fi

# Экспорт переменных для acme.sh
export CF_Token="$CF_Token"
export CF_Account_ID=""  # Не требуется для DNS-01

# Создание бэкапа
echo -e "${YELLOW}📦 Создание бэкапа текущих сертификатов...${NC}"
mkdir -p "$BACKUP_DIR"

if [[ -f "$SSL_DIR/nginx.crt" ]]; then
    cp "$SSL_DIR/nginx.crt" "$BACKUP_DIR/nginx.crt.backup"
    echo -e "${GREEN}✅ Сохранен: nginx.crt${NC}"
fi

if [[ -f "$SSL_DIR/nginx.key" ]]; then
    cp "$SSL_DIR/nginx.key" "$BACKUP_DIR/nginx.key.backup"
    echo -e "${GREEN}✅ Сохранен: nginx.key${NC}"
fi
echo ""

# Получение сертификата
echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}Получение Let's Encrypt сертификата${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""

echo -e "${YELLOW}Домены:${NC} $DOMAIN, $DOMAIN_WWW"
echo -e "${YELLOW}Email:${NC} $EMAIL"
echo -e "${YELLOW}DNS Provider:${NC} Cloudflare"
echo ""

echo -e "${YELLOW}🔐 Запуск acme.sh...${NC}"
"$ACME_HOME/acme.sh" --issue \
  --dns dns_cf \
  -d "$DOMAIN" \
  -d "$DOMAIN_WWW" \
  --keylength 2048 \
  --server letsencrypt

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✅ Сертификат успешно получен!${NC}"
else
    echo -e "${RED}❌ Ошибка при получении сертификата${NC}"
    echo -e "${YELLOW}Проверьте логи: cat $ACME_HOME/acme.sh.log${NC}"
    exit 1
fi
echo ""

# Установка сертификатов
echo -e "${YELLOW}📋 Установка сертификатов...${NC}"

"$ACME_HOME/acme.sh" --install-cert \
  -d "$DOMAIN" \
  --key-file "$SSL_DIR/letsencrypt-privkey.key" \
  --fullchain-file "$SSL_DIR/letsencrypt-fullchain.crt" \
  --cert-file "$SSL_DIR/letsencrypt-cert.crt" \
  --ca-file "$SSL_DIR/letsencrypt-chain.crt" \
  --reloadcmd "cd $PROJECT_ROOT && docker compose restart nginx"

# Установка правильных прав доступа
chmod 644 "$SSL_DIR/letsencrypt-fullchain.crt"
chmod 600 "$SSL_DIR/letsencrypt-privkey.key"
chmod 644 "$SSL_DIR/letsencrypt-cert.crt"
chmod 644 "$SSL_DIR/letsencrypt-chain.crt"

echo -e "${GREEN}✅ Сертификаты установлены${NC}"
echo ""

# Создание символических ссылок
echo -e "${YELLOW}🔗 Создание символических ссылок...${NC}"
cd "$SSL_DIR"
ln -sf letsencrypt-fullchain.crt nginx-fullchain.crt
ln -sf letsencrypt-fullchain.crt nginx.crt
ln -sf letsencrypt-privkey.key nginx.key
echo -e "${GREEN}✅ Символические ссылки созданы${NC}"
echo ""

# Проверка сертификата
echo -e "${YELLOW}🔍 Проверка сертификата...${NC}"
openssl x509 -in "$SSL_DIR/nginx-fullchain.crt" -noout -subject -issuer -dates -ext subjectAltName
echo ""

echo -e "${BLUE}============================================================================${NC}"
echo -e "${GREEN}✅ Let's Encrypt сертификаты успешно созданы!${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""
echo -e "${YELLOW}Информация:${NC}"
echo -e "  - Сертификат: Let's Encrypt (R3)"
echo -e "  - Срок действия: 90 дней"
echo -e "  - Автообновление: настроено через acme.sh cron"
echo -e "  - Бэкап: $BACKUP_DIR"
echo ""
echo -e "${YELLOW}Проверка HTTPS:${NC}"
echo -e "  curl -I https://ki.erni-gruppe.ch"
echo -e "  curl -I https://www.ki.erni-gruppe.ch"
echo ""
