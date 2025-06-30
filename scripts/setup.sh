#!/bin/bash
# Автоматизированный скрипт настройки ERNI-KI
# Автор: Альтэон Шульц (Tech Lead)

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Функции логирования
log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; exit 1; }

# Проверка зависимостей
check_dependencies() {
    log "Проверка системных зависимостей..."
    
    # Docker
    if ! command -v docker &> /dev/null; then
        error "Docker не установлен. Установите Docker: https://docs.docker.com/get-docker/"
    fi
    success "Docker найден: $(docker --version)"
    
    # Docker Compose
    if ! command -v docker compose &> /dev/null; then
        error "Docker Compose не установлен"
    fi
    success "Docker Compose найден: $(docker compose version)"
    
    # Node.js (опционально)
    if command -v node &> /dev/null; then
        success "Node.js найден: $(node --version)"
    else
        warning "Node.js не найден (требуется для разработки)"
    fi
    
    # Go (опционально)
    if command -v go &> /dev/null; then
        success "Go найден: $(go version)"
    else
        warning "Go не найден (требуется для сборки auth сервиса)"
    fi
    
    # OpenSSL для генерации ключей
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL не установлен (требуется для генерации секретных ключей)"
    fi
    success "OpenSSL найден"
}

# Создание директорий
create_directories() {
    log "Создание необходимых директорий..."
    
    directories=("data" "data/postgres" "data/redis" "data/ollama" "data/openwebui" "scripts" "logs")
    
    for dir in "${directories[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            success "Создана директория: $dir"
        else
            success "Директория уже существует: $dir"
        fi
    done
    
    # Установка правильных прав
    chmod 755 data/
    chmod 700 data/postgres
    success "Права доступа установлены"
}

# Копирование конфигурационных файлов
copy_config_files() {
    log "Копирование конфигурационных файлов..."
    
    # Docker Compose
    if [ ! -f "compose.yml" ]; then
        cp compose.yml.example compose.yml
        success "Скопирован compose.yml"
    else
        warning "compose.yml уже существует"
    fi
    
    # Конфигурации сервисов
    config_files=(
        "conf/cloudflare/config.example:conf/cloudflare/config.yml"
        "conf/mcposerver/config.example:conf/mcposerver/config.json"
        "conf/nginx/nginx.example:conf/nginx/nginx.conf"
        "conf/nginx/conf.d/default.example:conf/nginx/conf.d/default.conf"
        "conf/searxng/settings.yml.example:conf/searxng/settings.yml"
        "conf/searxng/uwsgi.ini.example:conf/searxng/uwsgi.ini"
    )
    
    for config in "${config_files[@]}"; do
        src="${config%:*}"
        dst="${config#*:}"
        
        if [ -f "$src" ] && [ ! -f "$dst" ]; then
            cp "$src" "$dst"
            success "Скопирован: $dst"
        elif [ ! -f "$src" ]; then
            warning "Исходный файл не найден: $src"
        else
            warning "Файл уже существует: $dst"
        fi
    done
}

# Копирование переменных окружения
copy_env_files() {
    log "Копирование файлов переменных окружения..."
    
    env_files=(
        "auth" "cloudflared" "db" "docling" "edgetts" 
        "mcposerver" "ollama" "openwebui" "redis" 
        "searxng" "tika" "watchtower"
    )
    
    for env_file in "${env_files[@]}"; do
        src="env/${env_file}.example"
        dst="env/${env_file}.env"
        
        if [ -f "$src" ] && [ ! -f "$dst" ]; then
            cp "$src" "$dst"
            success "Скопирован: $dst"
        elif [ ! -f "$src" ]; then
            warning "Исходный файл не найден: $src"
        else
            warning "Файл уже существует: $dst"
        fi
    done
}

# Генерация секретных ключей
generate_secrets() {
    log "Генерация секретных ключей..."
    
    # Генерация основного секретного ключа
    SECRET_KEY=$(openssl rand -hex 32)
    DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    success "Сгенерированы секретные ключи"
    
    # Обновление файлов окружения
    if [ -f "env/auth.env" ]; then
        sed -i "s/CHANGE_BEFORE_GOING_LIVE/$SECRET_KEY/g" env/auth.env
        success "Обновлен JWT_SECRET в env/auth.env"
    fi
    
    if [ -f "env/openwebui.env" ]; then
        sed -i "s/CHANGE_BEFORE_GOING_LIVE/$SECRET_KEY/g" env/openwebui.env
        sed -i "s/postgres:postgres@db/postgres:$DB_PASSWORD@db/g" env/openwebui.env
        success "Обновлен WEBUI_SECRET_KEY в env/openwebui.env"
    fi
    
    if [ -f "env/db.env" ]; then
        sed -i "s/POSTGRES_PASSWORD=postgres/POSTGRES_PASSWORD=$DB_PASSWORD/g" env/db.env
        success "Обновлен пароль БД в env/db.env"
    fi
    
    if [ -f "env/searxng.env" ]; then
        sed -i "s/YOUR-SECRET-KEY/$SECRET_KEY/g" env/searxng.env
        success "Обновлен SEARXNG_SECRET в env/searxng.env"
    fi
    
    # Сохранение ключей в файл для справки
    cat > .secrets_backup << EOF
# ERNI-KI Секретные ключи - $(date)
# ВНИМАНИЕ: Храните этот файл в безопасности!

SECRET_KEY=$SECRET_KEY
DB_PASSWORD=$DB_PASSWORD

# Эти ключи уже применены к конфигурационным файлам
EOF
    
    chmod 600 .secrets_backup
    success "Секретные ключи сохранены в .secrets_backup"
}

# Настройка домена
setup_domain() {
    log "Настройка домена..."
    
    echo -n "Введите ваш домен (или нажмите Enter для localhost): "
    read -r domain
    
    if [ -z "$domain" ]; then
        domain="localhost"
        warning "Используется localhost (только для локального доступа)"
    else
        success "Настроен домен: $domain"
    fi
    
    # Обновление конфигурации Nginx
    if [ -f "conf/nginx/conf.d/default.conf" ]; then
        sed -i "s/<domain-name>/$domain/g" conf/nginx/conf.d/default.conf
        success "Домен обновлен в конфигурации Nginx"
    fi
    
    # Обновление OpenWebUI URL
    if [ -f "env/openwebui.env" ]; then
        if [ "$domain" = "localhost" ]; then
            sed -i "s|WEBUI_URL=https://<domain-name>|WEBUI_URL=http://localhost|g" env/openwebui.env
        else
            sed -i "s/<domain-name>/$domain/g" env/openwebui.env
        fi
        success "URL обновлен в конфигурации OpenWebUI"
    fi
}

# Настройка Cloudflare (опционально)
setup_cloudflare() {
    log "Настройка Cloudflare туннеля (опционально)..."
    
    echo -n "Хотите настроить Cloudflare туннель? (y/N): "
    read -r setup_cf
    
    if [[ "$setup_cf" =~ ^[Yy]$ ]]; then
        echo -n "Введите токен Cloudflare туннеля: "
        read -r tunnel_token
        
        if [ -n "$tunnel_token" ] && [ -f "env/cloudflared.env" ]; then
            sed -i "s/add-your-cloudflare-tunnel-token-here/$tunnel_token/g" env/cloudflared.env
            success "Токен Cloudflare настроен"
        else
            warning "Токен не введен или файл не найден"
        fi
    else
        success "Cloudflare туннель пропущен"
    fi
}

# Проверка конфигурации
validate_config() {
    log "Проверка конфигурации..."
    
    # Проверка Docker Compose
    if docker compose config > /dev/null 2>&1; then
        success "Конфигурация Docker Compose валидна"
    else
        error "Ошибка в конфигурации Docker Compose"
    fi
    
    # Проверка секретных ключей
    if grep -r "CHANGE_BEFORE_GOING_LIVE" env/ > /dev/null 2>&1; then
        error "Найдены неизмененные секретные ключи!"
    fi
    
    if grep -r "YOUR-SECRET-KEY" env/ > /dev/null 2>&1; then
        error "Найдены неизмененные секретные ключи!"
    fi
    
    success "Все секретные ключи настроены"
}

# Создание полезных скриптов
create_helper_scripts() {
    log "Создание вспомогательных скриптов..."
    
    # Скрипт запуска
    cat > scripts/start.sh << 'EOF'
#!/bin/bash
echo "🚀 Запуск ERNI-KI..."
docker compose up -d
echo "✅ Сервисы запущены. Проверьте состояние: ./scripts/health_check.sh"
EOF
    
    # Скрипт остановки
    cat > scripts/stop.sh << 'EOF'
#!/bin/bash
echo "🛑 Остановка ERNI-KI..."
docker compose down
echo "✅ Сервисы остановлены"
EOF
    
    # Скрипт перезапуска
    cat > scripts/restart.sh << 'EOF'
#!/bin/bash
echo "🔄 Перезапуск ERNI-KI..."
docker compose down
docker compose up -d
echo "✅ Сервисы перезапущены"
EOF
    
    # Скрипт бэкапа
    cat > scripts/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "💾 Создание бэкапа..."
docker compose exec -T db pg_dump -U postgres openwebui > "$BACKUP_DIR/database.sql"
tar -czf "$BACKUP_DIR/configs.tar.gz" env/ conf/
echo "✅ Бэкап создан в $BACKUP_DIR"
EOF
    
    # Установка прав выполнения
    chmod +x scripts/*.sh
    success "Созданы вспомогательные скрипты в директории scripts/"
}

# Основная функция
main() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    ERNI-KI Setup Script                     ║"
    echo "║              Автоматизированная настройка системы           ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    check_dependencies
    echo ""
    
    create_directories
    echo ""
    
    copy_config_files
    echo ""
    
    copy_env_files
    echo ""
    
    generate_secrets
    echo ""
    
    setup_domain
    echo ""
    
    setup_cloudflare
    echo ""
    
    validate_config
    echo ""
    
    create_helper_scripts
    echo ""
    
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    Настройка завершена!                     ║"
    echo "║                                                              ║"
    echo "║  Следующие шаги:                                             ║"
    echo "║  1. Запустите: ./scripts/start.sh                           ║"
    echo "║  2. Проверьте: ./scripts/health_check.sh                    ║"
    echo "║  3. Откройте: http://localhost (или ваш домен)              ║"
    echo "║                                                              ║"
    echo "║  Документация: DEPLOYMENT_GUIDE.md                          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Запуск скрипта
main "$@"
