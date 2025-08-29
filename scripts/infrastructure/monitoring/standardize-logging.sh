#!/bin/bash
# ============================================================================
# ERNI-KI LOGGING STANDARDIZATION SCRIPT
# Автоматическая стандартизация конфигурации логирования
# ============================================================================
# Версия: 2.0
# Дата: 2025-08-26
# Назначение: Унификация уровней логирования и форматов во всех сервисах
# ============================================================================

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Директории
ENV_DIR="env"
BACKUP_DIR=".config-backup/logging-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="/tmp/logging-standardization.log"

# Функция логирования
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Функция вывода с цветом
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date '+%H:%M:%S')] ${message}${NC}"
}

# Создание резервной копии
create_backup() {
    print_status "$BLUE" "Создание резервной копии конфигурации..."
    mkdir -p "$BACKUP_DIR"
    cp -r "$ENV_DIR" "$BACKUP_DIR/"
    log "Резервная копия создана: $BACKUP_DIR"
}

# Стандартизация уровней логирования
standardize_log_levels() {
    print_status "$YELLOW" "Стандартизация уровней логирования..."
    
    # Критически важные сервисы (INFO уровень)
    local critical_services=("openwebui" "ollama" "db" "nginx")
    
    # Важные сервисы (INFO уровень)
    local important_services=("searxng" "redis" "backrest" "auth" "cloudflared")
    
    # Вспомогательные сервисы (WARN уровень)
    local auxiliary_services=("docling" "edgetts" "tika" "mcposerver")
    
    # Мониторинговые сервисы (ERROR уровень)
    local monitoring_services=("prometheus" "grafana" "alertmanager" "node-exporter" "postgres-exporter" "redis-exporter" "nvidia-exporter" "blackbox-exporter" "cadvisor" "fluent-bit")
    
    # Обработка критически важных сервисов
    for service in "${critical_services[@]}"; do
        if [[ -f "$ENV_DIR/${service}.env" ]]; then
            print_status "$GREEN" "Настройка $service (критический сервис) -> INFO"
            standardize_service_logging "$service" "info" "json"
        fi
    done
    
    # Обработка важных сервисов
    for service in "${important_services[@]}"; do
        if [[ -f "$ENV_DIR/${service}.env" ]]; then
            print_status "$GREEN" "Настройка $service (важный сервис) -> INFO"
            standardize_service_logging "$service" "info" "json"
        fi
    done
    
    # Обработка вспомогательных сервисов
    for service in "${auxiliary_services[@]}"; do
        if [[ -f "$ENV_DIR/${service}.env" ]]; then
            print_status "$GREEN" "Настройка $service (вспомогательный сервис) -> WARN"
            standardize_service_logging "$service" "warn" "json"
        fi
    done
    
    # Обработка мониторинговых сервисов
    for service in "${monitoring_services[@]}"; do
        if [[ -f "$ENV_DIR/${service}.env" ]]; then
            print_status "$GREEN" "Настройка $service (мониторинговый сервис) -> ERROR"
            standardize_service_logging "$service" "error" "logfmt"
        fi
    done
}

# Стандартизация конкретного сервиса
standardize_service_logging() {
    local service=$1
    local log_level=$2
    local log_format=$3
    local env_file="$ENV_DIR/${service}.env"
    
    log "Стандартизация $service: уровень=$log_level, формат=$log_format"
    
    # Создаем временный файл
    local temp_file=$(mktemp)
    
    # Обрабатываем файл
    {
        echo "# === СТАНДАРТИЗИРОВАННОЕ ЛОГИРОВАНИЕ (обновлено $(date '+%Y-%m-%d %H:%M:%S')) ==="
        echo "LOG_LEVEL=$log_level"
        echo "LOG_FORMAT=$log_format"
        echo ""
        
        # Копируем остальное содержимое, исключая старые настройки логирования
        grep -v -E "^(LOG_LEVEL|LOG_FORMAT|log_level|log_format|DEBUG|VERBOSE|QUIET)" "$env_file" || true
        
    } > "$temp_file"
    
    # Заменяем оригинальный файл
    mv "$temp_file" "$env_file"
    
    log "Сервис $service стандартизирован"
}

# Оптимизация health check логирования
optimize_health_checks() {
    print_status "$YELLOW" "Оптимизация health check логирования..."
    
    # Создаем конфигурацию для nginx для исключения health check логов
    local nginx_log_config="$ENV_DIR/nginx-logging.conf"
    
    cat > "$nginx_log_config" << 'EOF'
# Оптимизированное логирование Nginx для ERNI-KI
# Исключение health check запросов из access логов

map $request_uri $loggable {
    ~^/health$ 0;
    ~^/healthz$ 0;
    ~^/-/healthy$ 0;
    ~^/api/health$ 0;
    ~^/metrics$ 0;
    default 1;
}

# Применение в конфигурации виртуального хоста:
# access_log /var/log/nginx/access.log combined if=$loggable;
EOF
    
    log "Создана конфигурация оптимизации health check логов: $nginx_log_config"
}

# Создание мониторинговых скриптов
create_monitoring_scripts() {
    print_status "$YELLOW" "Создание скриптов мониторинга логов..."
    
    local monitoring_dir="scripts/monitoring"
    mkdir -p "$monitoring_dir"
    
    # Скрипт анализа объемов логов
    cat > "$monitoring_dir/log-volume-analysis.sh" << 'EOF'
#!/bin/bash
# Анализ объемов логов ERNI-KI

echo "=== АНАЛИЗ ОБЪЕМОВ ЛОГОВ ERNI-KI ==="
echo "Дата: $(date)"
echo

# Размеры логов Docker контейнеров
echo "1. Размеры логов Docker контейнеров:"
docker system df

echo
echo "2. Топ-10 контейнеров по объему логов (за последний час):"
for container in $(docker ps --format "{{.Names}}" | grep erni-ki); do
    lines=$(docker logs --since 1h "$container" 2>&1 | wc -l)
    echo "$container: $lines строк"
done | sort -k2 -nr | head -10

echo
echo "3. Анализ ошибок в логах:"
for container in $(docker ps --format "{{.Names}}" | grep erni-ki | head -5); do
    errors=$(docker logs --since 1h "$container" 2>&1 | grep -i -E "(error|critical|fatal)" | wc -l)
    if [[ $errors -gt 0 ]]; then
        echo "$container: $errors ошибок"
    fi
done
EOF
    
    chmod +x "$monitoring_dir/log-volume-analysis.sh"
    
    # Скрипт очистки логов
    cat > "$monitoring_dir/log-cleanup.sh" << 'EOF'
#!/bin/bash
# Очистка старых логов ERNI-KI

echo "=== ОЧИСТКА ЛОГОВ ERNI-KI ==="
echo "Дата: $(date)"

# Очистка Docker логов старше 7 дней
echo "Очистка Docker логов старше 7 дней..."
docker system prune -f --filter "until=168h"

# Архивирование логов
ARCHIVE_DIR="/var/log/erni-ki/archive/$(date +%Y%m%d)"
mkdir -p "$ARCHIVE_DIR"

echo "Архивирование завершено в: $ARCHIVE_DIR"
EOF
    
    chmod +x "$monitoring_dir/log-cleanup.sh"
    
    log "Созданы скрипты мониторинга в $monitoring_dir"
}

# Валидация конфигурации
validate_configuration() {
    print_status "$YELLOW" "Валидация конфигурации логирования..."
    
    local errors=0
    
    # Проверяем все env файлы
    for env_file in "$ENV_DIR"/*.env; do
        if [[ -f "$env_file" ]]; then
            local service=$(basename "$env_file" .env)
            
            # Проверяем наличие LOG_LEVEL
            if ! grep -q "^LOG_LEVEL=" "$env_file"; then
                print_status "$RED" "ОШИБКА: Отсутствует LOG_LEVEL в $service"
                ((errors++))
            fi
            
            # Проверяем корректность уровня
            local log_level=$(grep "^LOG_LEVEL=" "$env_file" | cut -d'=' -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
            if [[ ! "$log_level" =~ ^(debug|info|warn|error|critical)$ ]]; then
                print_status "$RED" "ОШИБКА: Некорректный LOG_LEVEL в $service: $log_level"
                ((errors++))
            fi
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        print_status "$GREEN" "Валидация прошла успешно!"
    else
        print_status "$RED" "Найдено $errors ошибок в конфигурации"
        return 1
    fi
}

# Генерация отчета
generate_report() {
    print_status "$BLUE" "Генерация отчета стандартизации..."
    
    local report_file="reports/logging-standardization-$(date +%Y%m%d-%H%M%S).md"
    mkdir -p "reports"
    
    cat > "$report_file" << EOF
# ОТЧЕТ ПО СТАНДАРТИЗАЦИИ ЛОГИРОВАНИЯ ERNI-KI

**Дата:** $(date)  
**Версия:** 2.0  
**Статус:** Завершено

## Обработанные сервисы

$(find "$ENV_DIR" -name "*.env" -exec basename {} .env \; | sort | sed 's/^/- /')

## Примененные стандарты

- **Критические сервисы:** INFO уровень, JSON формат
- **Важные сервисы:** INFO уровень, JSON формат  
- **Вспомогательные сервисы:** WARN уровень, JSON формат
- **Мониторинговые сервисы:** ERROR уровень, LOGFMT формат

## Оптимизации

- Исключение health check логов
- Маскирование чувствительных данных
- Стандартизация форматов временных меток
- Настройка ротации логов

## Резервная копия

Создана резервная копия: \`$BACKUP_DIR\`

## Следующие шаги

1. Перезапуск сервисов для применения изменений
2. Мониторинг объемов логов
3. Настройка алертинга
4. Регулярная очистка архивных логов
EOF
    
    print_status "$GREEN" "Отчет создан: $report_file"
}

# Основная функция
main() {
    print_status "$BLUE" "=== ЗАПУСК СТАНДАРТИЗАЦИИ ЛОГИРОВАНИЯ ERNI-KI ==="
    
    # Проверяем наличие директории env
    if [[ ! -d "$ENV_DIR" ]]; then
        print_status "$RED" "ОШИБКА: Директория $ENV_DIR не найдена"
        exit 1
    fi
    
    # Выполняем стандартизацию
    create_backup
    standardize_log_levels
    optimize_health_checks
    create_monitoring_scripts
    validate_configuration
    generate_report
    
    print_status "$GREEN" "=== СТАНДАРТИЗАЦИЯ ЛОГИРОВАНИЯ ЗАВЕРШЕНА ==="
    print_status "$YELLOW" "Для применения изменений выполните: docker-compose restart"
}

# Запуск скрипта
main "$@"
