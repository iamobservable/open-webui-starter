#!/bin/bash

# ============================================================================
# Скрипт создания Let's Encrypt сертификатов для ERNI-KI
# ============================================================================
# Описание: Автоматическое получение SSL сертификатов через certbot
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
WEBROOT_DIR="$PROJECT_ROOT/data/nginx/webroot"
LETSENCRYPT_DIR="$PROJECT_ROOT/data/letsencrypt"
BACKUP_DIR="$PROJECT_ROOT/.config-backup/ssl-$(date +%Y%m%d-%H%M%S)"

# Домены
DOMAINS="ki.erni-gruppe.ch,www.ki.erni-gruppe.ch"
EMAIL="diginnz1@gmail.com"

echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}Создание Let's Encrypt сертификатов для ERNI-KI${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""

# Проверка зависимостей
if ! command -v certbot &> /dev/null; then
    echo -e "${YELLOW}⚠️  certbot не установлен. Устанавливаю...${NC}"
    sudo apt-get update
    sudo apt-get install -y certbot
    echo -e "${GREEN}✅ certbot установлен${NC}"
fi

# Создание необходимых директорий
echo -e "${YELLOW}📁 Создание директорий...${NC}"
mkdir -p "$WEBROOT_DIR"
mkdir -p "$LETSENCRYPT_DIR"
mkdir -p "$BACKUP_DIR"
mkdir -p "$SSL_DIR"
echo -e "${GREEN}✅ Директории созданы${NC}"
echo ""

# Бэкап существующих сертификатов
echo -e "${YELLOW}📦 Создание бэкапа текущих сертификатов...${NC}"
if [[ -f "$SSL_DIR/nginx.crt" ]]; then
    cp "$SSL_DIR/nginx.crt" "$BACKUP_DIR/nginx.crt.backup"
    echo -e "${GREEN}✅ Сохранен: nginx.crt${NC}"
fi

if [[ -f "$SSL_DIR/nginx.key" ]]; then
    cp "$SSL_DIR/nginx.key" "$BACKUP_DIR/nginx.key.backup"
    echo -e "${GREEN}✅ Сохранен: nginx.key${NC}"
fi

if [[ -f "$SSL_DIR/nginx-fullchain.crt" ]]; then
    cp "$SSL_DIR/nginx-fullchain.crt" "$BACKUP_DIR/nginx-fullchain.crt.backup"
    echo -e "${GREEN}✅ Сохранен: nginx-fullchain.crt${NC}"
fi
echo ""

# Проверка DNS
echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}Проверка DNS записей${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""

echo -e "${YELLOW}Проверка ki.erni-gruppe.ch...${NC}"
KI_IP=$(dig +short ki.erni-gruppe.ch @8.8.8.8 | tail -1)
echo -e "DNS: ${GREEN}$KI_IP${NC}"

echo -e "${YELLOW}Проверка www.ki.erni-gruppe.ch...${NC}"
WWW_IP=$(dig +short www.ki.erni-gruppe.ch @8.8.8.8 | tail -1)
echo -e "DNS: ${GREEN}$WWW_IP${NC}"

# Получение текущего IP сервера
SERVER_IP=$(curl -s https://ipinfo.io/ip)
echo -e "${YELLOW}IP сервера:${NC} ${GREEN}$SERVER_IP${NC}"
echo ""

if [[ "$KI_IP" != "$SERVER_IP" ]]; then
    echo -e "${RED}⚠️  ВНИМАНИЕ: DNS еще не распространился полностью${NC}"
    echo -e "${YELLOW}ki.erni-gruppe.ch указывает на $KI_IP, но сервер имеет IP $SERVER_IP${NC}"
    echo -e "${YELLOW}Продолжить? (y/n)${NC}"
    read -r CONTINUE
    if [[ "$CONTINUE" != "y" ]]; then
        echo -e "${RED}Отменено пользователем${NC}"
        exit 1
    fi
fi

# Проверка доступности порта 80
echo -e "${YELLOW}🔍 Проверка доступности порта 80...${NC}"
if curl -I -s -m 5 http://ki.erni-gruppe.ch/.well-known/acme-challenge/test 2>&1 | grep -q "404"; then
    echo -e "${GREEN}✅ Порт 80 доступен${NC}"
else
    echo -e "${YELLOW}⚠️  Порт 80 может быть недоступен извне${NC}"
fi
echo ""

# Получение сертификата
echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}Получение Let's Encrypt сертификата${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""

echo -e "${YELLOW}Домены:${NC} $DOMAINS"
echo -e "${YELLOW}Email:${NC} $EMAIL"
echo -e "${YELLOW}Webroot:${NC} $WEBROOT_DIR"
echo ""

# Запуск certbot
echo -e "${YELLOW}🔐 Запуск certbot...${NC}"
sudo certbot certonly \
  --webroot \
  --webroot-path="$WEBROOT_DIR" \
  --email "$EMAIL" \
  --agree-tos \
  --no-eff-email \
  --non-interactive \
  --expand \
  -d ki.erni-gruppe.ch \
  -d www.ki.erni-gruppe.ch

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✅ Сертификат успешно получен!${NC}"
else
    echo -e "${RED}❌ Ошибка при получении сертификата${NC}"
    echo -e "${YELLOW}Проверьте логи certbot: sudo journalctl -u certbot${NC}"
    exit 1
fi
echo ""

# Копирование сертификатов в nginx директорию
echo -e "${YELLOW}📋 Копирование сертификатов в nginx директорию...${NC}"

CERT_PATH="/etc/letsencrypt/live/ki.erni-gruppe.ch"

if [[ ! -d "$CERT_PATH" ]]; then
    echo -e "${RED}❌ Ошибка: Сертификаты не найдены в $CERT_PATH${NC}"
    exit 1
fi

sudo cp "$CERT_PATH/fullchain.pem" "$SSL_DIR/letsencrypt-fullchain.crt"
sudo cp "$CERT_PATH/privkey.pem" "$SSL_DIR/letsencrypt-privkey.key"
sudo cp "$CERT_PATH/cert.pem" "$SSL_DIR/letsencrypt-cert.crt"
sudo cp "$CERT_PATH/chain.pem" "$SSL_DIR/letsencrypt-chain.crt"

# Установка правильных прав доступа
sudo chown $(whoami):$(whoami) "$SSL_DIR/letsencrypt-"*
chmod 644 "$SSL_DIR/letsencrypt-fullchain.crt"
chmod 600 "$SSL_DIR/letsencrypt-privkey.key"
chmod 644 "$SSL_DIR/letsencrypt-cert.crt"
chmod 644 "$SSL_DIR/letsencrypt-chain.crt"

echo -e "${GREEN}✅ Сертификаты скопированы${NC}"
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
echo -e "${GREEN}✅ Let's Encrypt сертификаты успешно созданы и установлены!${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""
echo -e "${YELLOW}Бэкап сохранен в:${NC} $BACKUP_DIR"
echo -e "${YELLOW}Сертификаты:${NC} $SSL_DIR"
echo ""
echo -e "${YELLOW}Следующие шаги:${NC}"
echo -e "1. Перезагрузите nginx: ${GREEN}docker compose restart nginx${NC}"
echo -e "2. Проверьте HTTPS: ${GREEN}curl -I https://ki.erni-gruppe.ch${NC}"
echo ""
