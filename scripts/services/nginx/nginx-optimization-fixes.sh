#!/bin/bash

# ERNI-KI Nginx Optimization Fixes
# Автоматическое применение оптимизаций из аудита от 25.08.2025
# Версия: 1.0

set -euo pipefail

# === Конфигурация ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NGINX_CONF_DIR="$PROJECT_ROOT/conf/nginx"
BACKUP_DIR="$PROJECT_ROOT/.config-backup/nginx-optimization-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$PROJECT_ROOT/logs/nginx-optimization.log"

# === Функции логирования ===
log() {
    echo "[$(date -Iseconds)] INFO: $*" | tee -a "$LOG_FILE"
}

success() {
    echo "[$(date -Iseconds)] SUCCESS: $*" | tee -a "$LOG_FILE"
}

warning() {
    echo "[$(date -Iseconds)] WARNING: $*" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date -Iseconds)] ERROR: $*" | tee -a "$LOG_FILE"
}

# === Создание директорий ===
mkdir -p "$(dirname "$LOG_FILE")" "$BACKUP_DIR"

# === Создание backup ===
create_backup() {
    log "Создание backup конфигурации nginx..."
    
    if cp -r "$NGINX_CONF_DIR" "$BACKUP_DIR/"; then
        success "Backup создан: $BACKUP_DIR"
        echo "$BACKUP_DIR" > "$PROJECT_ROOT/.config-backup/nginx-last-backup.txt"
    else
        error "Не удалось создать backup"
        exit 1
    fi
}

# === Проверка текущей конфигурации ===
check_current_config() {
    log "Проверка текущей конфигурации nginx..."
    
    if docker exec erni-ki-nginx-1 nginx -t >/dev/null 2>&1; then
        success "Текущая конфигурация валидна"
    else
        error "Текущая конфигурация содержит ошибки"
        docker exec erni-ki-nginx-1 nginx -t
        exit 1
    fi
}

# === Исправление 1: Добавление Gzip сжатия ===
fix_gzip_compression() {
    log "Исправление 1: Добавление Gzip сжатия в nginx.conf..."
    
    local nginx_conf="$NGINX_CONF_DIR/nginx.conf"
    
    # Проверяем, есть ли уже gzip настройки
    if grep -q "gzip on" "$nginx_conf"; then
        warning "Gzip уже настроен в nginx.conf"
        return 0
    fi
    
    # Находим строку после которой вставить gzip настройки
    local insert_line=$(grep -n "include /etc/nginx/mime.types;" "$nginx_conf" | cut -d: -f1)
    
    if [[ -z "$insert_line" ]]; then
        error "Не найдена строка для вставки gzip настроек"
        return 1
    fi
    
    # Создаем временный файл с gzip настройками
    cat > /tmp/gzip_config.txt << 'EOF'

    # Gzip сжатие для оптимизации производительности
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;
EOF
    
    # Вставляем gzip настройки после mime.types
    sed -i "${insert_line}r /tmp/gzip_config.txt" "$nginx_conf"
    rm /tmp/gzip_config.txt
    
    success "Gzip сжатие добавлено в nginx.conf"
}

# === Исправление 2: Удаление дублирующихся WebSocket директив ===
fix_websocket_duplication() {
    log "Исправление 2: Удаление дублирующихся WebSocket директив..."
    
    local default_conf="$NGINX_CONF_DIR/conf.d/default.conf"
    
    # Проверяем наличие дублирования
    local websocket_count=$(grep -c "map \$http_upgrade \$connection_upgrade" "$default_conf" || echo "0")
    
    if [[ "$websocket_count" -eq 0 ]]; then
        warning "WebSocket mapping не найден в default.conf"
        return 0
    fi
    
    # Удаляем дублирующийся блок (строки 74-77)
    sed -i '74,77d' "$default_conf"
    
    success "Дублирующиеся WebSocket директивы удалены"
}

# === Исправление 3: Принудительное добавление Security Headers ===
fix_security_headers() {
    log "Исправление 3: Исправление Security Headers..."
    
    local default_conf="$NGINX_CONF_DIR/conf.d/default.conf"
    
    # Находим основной location / блок (около строки 804)
    local location_line=$(grep -n "location / {" "$default_conf" | head -1 | cut -d: -f1)
    
    if [[ -z "$location_line" ]]; then
        error "Не найден основной location / блок"
        return 1
    fi
    
    # Находим строку с proxy_pass в этом блоке
    local proxy_line=$(sed -n "${location_line},/^[[:space:]]*}/p" "$default_conf" | grep -n "proxy_pass" | head -1 | cut -d: -f1)
    
    if [[ -z "$proxy_line" ]]; then
        error "Не найдена строка proxy_pass в location /"
        return 1
    fi
    
    # Вычисляем абсолютную строку для вставки
    local insert_line=$((location_line + proxy_line))
    
    # Создаем временный файл с security headers
    cat > /tmp/security_headers.txt << 'EOF'
        
        # Принудительное добавление security headers
        add_header X-Frame-Options SAMEORIGIN always;
        add_header X-Content-Type-Options nosniff always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
EOF
    
    # Вставляем security headers после proxy_pass
    sed -i "${insert_line}r /tmp/security_headers.txt" "$default_conf"
    rm /tmp/security_headers.txt
    
    success "Security headers исправлены"
}

# === Исправление 4: Комментирование неиспользуемых upstream блоков ===
fix_unused_upstreams() {
    log "Исправление 4: Комментирование неиспользуемых upstream блоков..."
    
    local default_conf="$NGINX_CONF_DIR/conf.d/default.conf"
    
    # Комментируем redisUpstream (если не используется)
    if grep -q "upstream redisUpstream" "$default_conf" && ! grep -q "proxy_pass.*redisUpstream" "$default_conf"; then
        sed -i '/upstream redisUpstream/,/^}/s/^/# /' "$default_conf"
        success "redisUpstream закомментирован"
    fi
    
    # Комментируем authUpstream (если не используется)
    if grep -q "upstream authUpstream" "$default_conf" && ! grep -q "proxy_pass.*authUpstream" "$default_conf"; then
        sed -i '/upstream authUpstream/,/^}/s/^/# /' "$default_conf"
        success "authUpstream закомментирован"
    fi
}

# === Проверка новой конфигурации ===
test_new_config() {
    log "Проверка новой конфигурации nginx..."
    
    if docker exec erni-ki-nginx-1 nginx -t >/dev/null 2>&1; then
        success "Новая конфигурация валидна"
        return 0
    else
        error "Новая конфигурация содержит ошибки:"
        docker exec erni-ki-nginx-1 nginx -t
        return 1
    fi
}

# === Применение изменений ===
apply_changes() {
    log "Применение изменений без downtime..."
    
    if docker exec erni-ki-nginx-1 nginx -s reload; then
        success "Nginx перезагружен успешно"
    else
        error "Ошибка при перезагрузке nginx"
        return 1
    fi
}

# === Проверка результатов ===
verify_fixes() {
    log "Проверка результатов оптимизации..."
    
    # Проверка gzip
    if curl -s -H "Accept-Encoding: gzip" -I http://localhost:8080/ | grep -q "Content-Encoding: gzip"; then
        success "Gzip сжатие работает"
    else
        warning "Gzip сжатие не обнаружено"
    fi
    
    # Проверка security headers
    local headers_count=$(curl -s -I https://localhost:443/ -k | grep -E "(X-Frame-Options|X-Content-Type-Options|X-XSS-Protection|Strict-Transport-Security)" | wc -l)
    
    if [[ "$headers_count" -ge 3 ]]; then
        success "Security headers работают ($headers_count из 4)"
    else
        warning "Security headers не все работают ($headers_count из 4)"
    fi
    
    # Проверка общей работоспособности
    if curl -s -o /dev/null -w "%{http_code}" https://localhost:443/ -k | grep -q "200"; then
        success "Основной сайт доступен"
    else
        error "Основной сайт недоступен"
    fi
}

# === Откат изменений ===
rollback_changes() {
    log "Откат изменений к предыдущей конфигурации..."
    
    local last_backup
    if [[ -f "$PROJECT_ROOT/.config-backup/nginx-last-backup.txt" ]]; then
        last_backup=$(cat "$PROJECT_ROOT/.config-backup/nginx-last-backup.txt")
    else
        error "Не найден путь к последнему backup"
        return 1
    fi
    
    if [[ -d "$last_backup" ]]; then
        cp -r "$last_backup/nginx/"* "$NGINX_CONF_DIR/"
        docker exec erni-ki-nginx-1 nginx -s reload
        success "Откат выполнен успешно"
    else
        error "Backup директория не найдена: $last_backup"
        return 1
    fi
}

# === Основная функция ===
main() {
    log "=== Запуск оптимизации Nginx ERNI-KI ==="
    
    # Проверка окружения
    if ! docker ps | grep -q "erni-ki-nginx-1"; then
        error "Контейнер erni-ki-nginx-1 не найден"
        exit 1
    fi
    
    # Выполнение исправлений
    create_backup
    check_current_config
    
    log "Применение исправлений..."
    fix_gzip_compression
    fix_websocket_duplication
    fix_security_headers
    fix_unused_upstreams
    
    # Проверка и применение
    if test_new_config; then
        apply_changes
        verify_fixes
        
        log "=== Оптимизация завершена успешно ==="
        log "Backup сохранен в: $BACKUP_DIR"
        log "Для отката используйте: $0 --rollback"
    else
        error "Конфигурация содержит ошибки, откат..."
        rollback_changes
        exit 1
    fi
}

# === Обработка аргументов ===
case "${1:-}" in
    --rollback)
        rollback_changes
        ;;
    --help)
        echo "Использование: $0 [--rollback|--help]"
        echo "  --rollback  Откат к предыдущей конфигурации"
        echo "  --help      Показать эту справку"
        ;;
    *)
        main "$@"
        ;;
esac
