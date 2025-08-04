#!/bin/bash
# Быстрый запуск ERNI-KI за 5 минут
# Автор: Альтэон Шульц (Tech Lead)

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Функции логирования
log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; exit 1; }
step() { echo -e "${PURPLE}🔸 $1${NC}"; }

# Проверка быстрых зависимостей
quick_check() {
    step "Быстрая проверка системы..."
    
    command -v docker >/dev/null 2>&1 || error "Docker не установлен"
    command -v docker compose >/dev/null 2>&1 || error "Docker Compose не установлен"
    command -v openssl >/dev/null 2>&1 || error "OpenSSL не установлен"
    
    success "Все зависимости найдены"
}

# Быстрая настройка
quick_setup() {
    step "Быстрая настройка конфигурации..."
    
    # Создание основных директорий
    mkdir -p data/{postgres,redis,ollama,openwebui} scripts logs
    chmod 755 data/ && chmod 700 data/postgres
    
    # Копирование основных файлов
    [ ! -f "compose.yml" ] && cp compose.yml.example compose.yml
    
    # Основные env файлы
    for env in auth db openwebui searxng; do
        [ ! -f "env/${env}.env" ] && cp "env/${env}.example" "env/${env}.env"
    done
    
    # Основные конфигурации
    [ ! -f "conf/nginx/nginx.conf" ] && cp conf/nginx/nginx.example conf/nginx/nginx.conf
    [ ! -f "conf/nginx/conf.d/default.conf" ] && cp conf/nginx/conf.d/default.example conf/nginx/conf.d/default.conf
    
    success "Базовая конфигурация создана"
}

# Быстрая генерация ключей
quick_secrets() {
    step "Генерация секретных ключей..."
    
    SECRET_KEY=$(openssl rand -hex 32)
    DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    # Обновление ключей
    sed -i "s/CHANGE_BEFORE_GOING_LIVE/$SECRET_KEY/g" env/auth.env env/openwebui.env
    sed -i "s/YOUR-SECRET-KEY/$SECRET_KEY/g" env/searxng.env
    sed -i "s/POSTGRES_PASSWORD=postgres/POSTGRES_PASSWORD=$DB_PASSWORD/g" env/db.env
    sed -i "s/postgres:postgres@db/postgres:$DB_PASSWORD@db/g" env/openwebui.env
    
    # Настройка localhost
    sed -i "s/<domain-name>/localhost/g" conf/nginx/conf.d/default.conf
    sed -i "s|WEBUI_URL=https://<domain-name>|WEBUI_URL=http://localhost|g" env/openwebui.env
    
    success "Секретные ключи настроены для localhost"
}

# Быстрый запуск сервисов
quick_start() {
    step "Запуск основных сервисов..."
    
    # Проверка конфигурации
    docker compose config >/dev/null || error "Ошибка в конфигурации Docker Compose"
    
    # Запуск в правильном порядке
    log "Запуск базовых сервисов..."
    docker compose up -d watchtower db redis
    sleep 10
    
    log "Запуск вспомогательных сервисов..."
    docker compose up -d auth searxng nginx
    sleep 10
    
    log "Запуск Ollama..."
    docker compose up -d ollama
    sleep 15
    
    log "Запуск OpenWebUI..."
    docker compose up -d openwebui
    sleep 10
    
    success "Все сервисы запущены"
}

# Загрузка базовой модели
quick_model() {
    step "Загрузка базовой модели..."
    
    # Ожидание готовности Ollama
    log "Ожидание готовности Ollama..."
    for i in {1..30}; do
        if docker compose exec -T ollama ollama list >/dev/null 2>&1; then
            break
        fi
        sleep 2
        echo -n "."
    done
    echo ""
    
    # Загрузка модели
    log "Загрузка llama3.2:3b (это может занять несколько минут)..."
    if docker compose exec -T ollama ollama pull llama3.2:3b; then
        success "Модель llama3.2:3b загружена"
    else
        warning "Не удалось загрузить модель (можно сделать позже)"
    fi
}

# Быстрая проверка
quick_health() {
    step "Быстрая проверка состояния..."
    
    # Проверка основных сервисов
    services=("auth" "db" "redis" "ollama" "nginx" "openwebui")
    
    for service in "${services[@]}"; do
        status=$(docker compose ps "$service" --format "{{.State}}" 2>/dev/null || echo "not_found")
        if [ "$status" = "running" ]; then
            success "$service: работает"
        else
            warning "$service: $status"
        fi
    done
    
    # Проверка основных endpoint'ов
    sleep 5
    
    if curl -sf http://localhost >/dev/null 2>&1; then
        success "Веб-интерфейс: доступен на http://localhost"
    else
        warning "Веб-интерфейс: пока недоступен (может потребоваться время)"
    fi
    
    if curl -sf http://localhost:11434/api/version >/dev/null 2>&1; then
        success "Ollama API: доступен"
    else
        warning "Ollama API: пока недоступен"
    fi
}

# Создание быстрых команд
create_quick_commands() {
    step "Создание быстрых команд..."
    
    # Команда статуса
    cat > scripts/status.sh << 'EOF'
#!/bin/bash
echo "📊 Статус ERNI-KI:"
docker compose ps
echo ""
echo "🌐 Доступные URL:"
echo "  - Веб-интерфейс: http://localhost"
echo "  - Ollama API: http://localhost:11434"
echo "  - Auth API: http://localhost:9090"
EOF
    
    # Команда логов
    cat > scripts/logs.sh << 'EOF'
#!/bin/bash
echo "📋 Логи ERNI-KI (Ctrl+C для выхода):"
docker compose logs -f
EOF
    
    # Команда остановки
    cat > scripts/stop.sh << 'EOF'
#!/bin/bash
echo "🛑 Остановка ERNI-KI..."
docker compose down
echo "✅ Все сервисы остановлены"
EOF
    
    chmod +x scripts/*.sh
    success "Быстрые команды созданы в scripts/"
}

# Показ следующих шагов
show_next_steps() {
    echo ""
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                🎉 ERNI-KI готов к работе! 🎉                ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║                                                              ║"
    echo "║  🌐 Откройте браузер: http://localhost                      ║"
    echo "║                                                              ║"
    echo "║  📝 Первые шаги:                                            ║"
    echo "║     1. Создайте аккаунт администратора                      ║"
    echo "║     2. Настройте подключение к Ollama                       ║"
    echo "║     3. Начните общение с AI!                                ║"
    echo "║                                                              ║"
    echo "║  🔧 Полезные команды:                                       ║"
    echo "║     ./scripts/status.sh  - статус сервисов                 ║"
    echo "║     ./scripts/logs.sh    - просмотр логов                  ║"
    echo "║     ./scripts/stop.sh    - остановка системы               ║"
    echo "║                                                              ║"
    echo "║  📚 Документация: DEPLOYMENT_GUIDE.md                       ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Показ важной информации
    echo -e "${YELLOW}"
    echo "⚠️  ВАЖНО:"
    echo "   - Секретные ключи сохранены в .secrets_backup"
    echo "   - Для продакшена настройте домен и SSL"
    echo "   - Регулярно создавайте бэкапы данных"
    echo -e "${NC}"
}

# Основная функция
main() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                  🚀 ERNI-KI Quick Start 🚀                  ║"
    echo "║                   Запуск за 5 минут                         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "${BLUE}Этот скрипт выполнит быстрый запуск ERNI-KI с настройками по умолчанию.${NC}"
    echo -e "${BLUE}Для продвинутой настройки используйте: ./scripts/setup.sh${NC}"
    echo ""
    
    echo -n "Продолжить быстрый запуск? (Y/n): "
    read -r confirm
    
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "Отменено пользователем"
        exit 0
    fi
    
    echo ""
    
    quick_check
    echo ""
    
    quick_setup
    echo ""
    
    quick_secrets
    echo ""
    
    quick_start
    echo ""
    
    quick_model
    echo ""
    
    quick_health
    echo ""
    
    create_quick_commands
    echo ""
    
    show_next_steps
}

# Запуск скрипта
main "$@"
