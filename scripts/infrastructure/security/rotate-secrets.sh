#!/bin/bash

# =============================================================================
# ERNI-KI: Скрипт ротации секретов
# =============================================================================
# Автоматическая ротация паролей для PostgreSQL, Redis, Backrest
# Использование: ./scripts/rotate-secrets.sh [--dry-run] [--service SERVICE]
# =============================================================================

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции логирования
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

# Проверка зависимостей
check_dependencies() {
    local deps=("docker-compose" "openssl")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error "Зависимость '$dep' не найдена. Установите её перед запуском скрипта."
        fi
    done
}

# Проверка, что мы в корне проекта
check_project_root() {
    if [ ! -f "compose.yml" ] || [ ! -d "env" ] || [ ! -d "secrets" ]; then
        error "Скрипт должен запускаться из корня проекта ERNI-KI"
    fi
}

# Создание backup старых секретов
backup_secrets() {
    local backup_dir=".config-backup/secrets-rotation-$(date +%Y%m%d-%H%M%S)"
    log "Создание backup секретов в $backup_dir"
    
    mkdir -p "$backup_dir"
    cp -r secrets/ "$backup_dir/"
    cp -r env/ "$backup_dir/"
    
    success "Backup создан в $backup_dir"
}

# Генерация новых паролей
generate_passwords() {
    log "Генерация новых безопасных паролей..."
    
    NEW_POSTGRES_PASSWORD=$(openssl rand -base64 32)
    NEW_REDIS_PASSWORD=$(openssl rand -base64 32)
    NEW_BACKREST_PASSWORD=$(openssl rand -base64 32)
    
    success "Новые пароли сгенерированы"
}

# Обновление PostgreSQL пароля
rotate_postgres_password() {
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Обновление PostgreSQL пароля"
        return
    fi
    
    log "Обновление PostgreSQL пароля..."
    
    # Обновление env файла
    sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${NEW_POSTGRES_PASSWORD}/" env/db.env
    
    # Обновление secrets файла
    echo "$NEW_POSTGRES_PASSWORD" > secrets/postgres_password.txt
    chmod 600 secrets/postgres_password.txt
    
    success "PostgreSQL пароль обновлен"
}

# Обновление Redis пароля
rotate_redis_password() {
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Обновление Redis пароля"
        return
    fi
    
    log "Обновление Redis пароля..."
    
    # Обновление env файла
    sed -i "s/REDIS_ARGS=\"--requirepass [^\"]*\"/REDIS_ARGS=\"--requirepass ${NEW_REDIS_PASSWORD} --maxmemory 1gb --maxmemory-policy allkeys-lru\"/" env/redis.env
    
    # Обновление secrets файла
    echo "$NEW_REDIS_PASSWORD" > secrets/redis_password.txt
    chmod 600 secrets/redis_password.txt
    
    success "Redis пароль обновлен"
}

# Обновление Backrest пароля
rotate_backrest_password() {
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Обновление Backrest пароля"
        return
    fi
    
    log "Обновление Backrest пароля..."
    
    # Обновление env файла
    sed -i "s/BACKREST_PASSWORD=.*/BACKREST_PASSWORD=${NEW_BACKREST_PASSWORD}/" env/backrest.env
    sed -i "s/RESTIC_PASSWORD=.*/RESTIC_PASSWORD=${NEW_BACKREST_PASSWORD}/" env/backrest.env
    
    # Обновление secrets файла
    echo "$NEW_BACKREST_PASSWORD" > secrets/backrest_password.txt
    chmod 600 secrets/backrest_password.txt
    
    success "Backrest пароль обновлен"
}

# Перезапуск сервисов
restart_services() {
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Перезапуск сервисов: $1"
        return
    fi
    
    local services="$1"
    log "Перезапуск сервисов: $services"
    
    # Graceful restart с проверкой здоровья
    for service in $services; do
        log "Перезапуск $service..."
        docker-compose restart "$service"
        
        # Ожидание восстановления здоровья сервиса
        local max_attempts=30
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            if docker-compose ps "$service" | grep -q "healthy\|Up"; then
                success "$service успешно перезапущен"
                break
            fi
            
            if [ $attempt -eq $max_attempts ]; then
                error "$service не восстановился после перезапуска"
            fi
            
            log "Ожидание восстановления $service (попытка $attempt/$max_attempts)..."
            sleep 10
            ((attempt++))
        done
    done
}

# Проверка работоспособности после ротации
verify_rotation() {
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Проверка работоспособности"
        return
    fi
    
    log "Проверка работоспособности после ротации..."
    
    # Проверка PostgreSQL
    if docker-compose exec -T db pg_isready -U postgres; then
        success "PostgreSQL работает корректно"
    else
        error "PostgreSQL недоступен после ротации"
    fi
    
    # Проверка Redis
    if docker-compose exec -T redis redis-cli ping | grep -q "PONG"; then
        success "Redis работает корректно"
    else
        error "Redis недоступен после ротации"
    fi
    
    # Проверка Backrest
    if curl -s http://localhost:9898/health >/dev/null; then
        success "Backrest работает корректно"
    else
        warning "Backrest может быть недоступен (проверьте вручную)"
    fi
}

# Основная функция
main() {
    local service_filter=""
    DRY_RUN=false
    
    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --service)
                service_filter="$2"
                shift 2
                ;;
            --help|-h)
                echo "Использование: $0 [--dry-run] [--service SERVICE]"
                echo "  --dry-run    Показать что будет сделано без выполнения"
                echo "  --service    Ротировать только указанный сервис (postgres|redis|backrest)"
                exit 0
                ;;
            *)
                error "Неизвестный аргумент: $1"
                ;;
        esac
    done
    
    log "🔄 Запуск ротации секретов ERNI-KI..."
    
    if [ "$DRY_RUN" = true ]; then
        warning "РЕЖИМ ТЕСТИРОВАНИЯ - изменения не будут применены"
    fi
    
    check_dependencies
    check_project_root
    
    if [ "$DRY_RUN" = false ]; then
        backup_secrets
    fi
    
    generate_passwords
    
    # Ротация по сервисам
    case "$service_filter" in
        "postgres")
            rotate_postgres_password
            restart_services "db"
            ;;
        "redis")
            rotate_redis_password
            restart_services "redis"
            ;;
        "backrest")
            rotate_backrest_password
            restart_services "backrest"
            ;;
        "")
            # Ротация всех сервисов
            rotate_postgres_password
            rotate_redis_password
            rotate_backrest_password
            restart_services "db redis backrest"
            ;;
        *)
            error "Неизвестный сервис: $service_filter"
            ;;
    esac
    
    verify_rotation
    
    success "✅ Ротация секретов завершена успешно!"
    
    if [ "$DRY_RUN" = false ]; then
        warning "ВАЖНО: Сохраните новые пароли в безопасном месте!"
        echo "PostgreSQL: $NEW_POSTGRES_PASSWORD"
        echo "Redis: $NEW_REDIS_PASSWORD"
        echo "Backrest: $NEW_BACKREST_PASSWORD"
    fi
}

# Запуск скрипта
main "$@"
