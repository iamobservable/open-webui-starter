#!/bin/bash
# Скрипт генерации SSL сертификатов для ERNI-KI
# Создает самоподписанные сертификаты для локального использования

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции логирования
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Конфигурация
SSL_DIR="$(dirname "$0")"
DOMAIN_NAME="${1:-erni-ki.local}"
COUNTRY="DE"
STATE="Baden-Württemberg"
CITY="Stuttgart"
ORGANIZATION="ERNI-KI"
ORGANIZATIONAL_UNIT="AI Infrastructure"
EMAIL="admin@erni-ki.local"

# Создание директории для SSL сертификатов
mkdir -p "$SSL_DIR"
cd "$SSL_DIR"

log "Генерация SSL сертификатов для домена: $DOMAIN_NAME"

# Создание конфигурационного файла для OpenSSL
cat > openssl.conf << EOF
[req]
default_bits = 4096
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=$COUNTRY
ST=$STATE
L=$CITY
O=$ORGANIZATION
OU=$ORGANIZATIONAL_UNIT
CN=$DOMAIN_NAME
emailAddress=$EMAIL

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN_NAME
DNS.2 = *.$DOMAIN_NAME
DNS.3 = localhost
DNS.4 = *.localhost
DNS.5 = diz.zone
DNS.6 = *.diz.zone
IP.1 = 127.0.0.1
IP.2 = ::1
IP.3 = 192.168.1.100
EOF

# Генерация приватного ключа
log "Генерация приватного ключа..."
openssl genrsa -out nginx.key 4096

# Генерация запроса на сертификат (CSR)
log "Генерация запроса на сертификат..."
openssl req -new -key nginx.key -out nginx.csr -config openssl.conf

# Генерация самоподписанного сертификата
log "Генерация самоподписанного сертификата..."
openssl x509 -req -in nginx.csr -signkey nginx.key -out nginx.crt -days 365 -extensions v3_req -extfile openssl.conf

# Создание комбинированного файла (если нужен)
log "Создание комбинированного файла сертификата..."
cat nginx.crt nginx.key > nginx.pem

# Генерация DH параметров для повышенной безопасности
log "Генерация DH параметров (это может занять несколько минут)..."
openssl dhparam -out dhparam.pem 2048

# Установка правильных прав доступа
chmod 600 nginx.key nginx.pem
chmod 644 nginx.crt nginx.csr dhparam.pem
chmod 644 openssl.conf

# Создание конфигурации Nginx для SSL
cat > nginx-ssl.conf << 'EOF'
# SSL конфигурация для ERNI-KI
# Добавить в server блок nginx

# SSL сертификаты
ssl_certificate /etc/nginx/ssl/nginx.crt;
ssl_certificate_key /etc/nginx/ssl/nginx.key;
ssl_dhparam /etc/nginx/ssl/dhparam.pem;

# SSL протоколы и шифры
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
ssl_prefer_server_ciphers on;

# SSL сессии
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
ssl_session_tickets off;

# OCSP Stapling
ssl_stapling on;
ssl_stapling_verify on;

# Заголовки безопасности
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
add_header X-Frame-Options DENY always;
add_header X-Content-Type-Options nosniff always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
EOF

# Проверка сертификата
log "Проверка созданного сертификата..."
openssl x509 -in nginx.crt -text -noout | grep -E "(Subject:|DNS:|IP Address:|Not After)"

# Вывод информации
success "SSL сертификаты успешно созданы!"
echo ""
echo "Созданные файлы:"
echo "  - nginx.key: Приватный ключ"
echo "  - nginx.crt: Сертификат"
echo "  - nginx.csr: Запрос на сертификат"
echo "  - nginx.pem: Комбинированный файл"
echo "  - dhparam.pem: DH параметры"
echo "  - openssl.conf: Конфигурация OpenSSL"
echo "  - nginx-ssl.conf: Пример конфигурации Nginx"
echo ""
echo "Домены в сертификате:"
echo "  - $DOMAIN_NAME"
echo "  - *.$DOMAIN_NAME"
echo "  - localhost"
echo "  - *.localhost"
echo "  - diz.zone"
echo "  - *.diz.zone"
echo ""
warning "ВНИМАНИЕ: Это самоподписанный сертификат!"
warning "Браузеры будут показывать предупреждение о безопасности."
warning "Для production используйте сертификаты от доверенного CA (например, Let's Encrypt)."
echo ""
log "Для использования в Docker Compose убедитесь, что volume смонтирован:"
log "  volumes:"
log "    - ./conf/nginx/ssl:/etc/nginx/ssl"

# Очистка временных файлов
rm -f nginx.csr openssl.conf

success "Генерация SSL сертификатов завершена!"
