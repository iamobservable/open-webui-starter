#!/bin/bash
# Скрипт проверки локального бэкапа ERNI-KI
# Проверяет состояние бэкапов в директории .config-backup

set -euo pipefail

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
    exit 1
}

# Проверка директории бэкапа
check_backup_directory() {
    log "Проверка директории локального бэкапа..."
    
    if [ ! -d ".config-backup" ]; then
        error "Директория .config-backup не найдена"
    fi
    
    if [ ! "$(ls -A .config-backup 2>/dev/null)" ]; then
        warning "Директория .config-backup пуста"
        echo "Возможные причины:"
        echo "1. Репозиторий еще не создан в Backrest"
        echo "2. Бэкап еще не выполнялся"
        echo "3. Ошибка в конфигурации"
        return 1
    fi
    
    success "Директория .config-backup содержит данные"
    return 0
}

# Проверка с помощью restic
check_with_restic() {
    log "Проверка бэкапа с помощью restic..."
    
    # Получение пароля из файла секретов
    if [ -f ".backrest_secrets" ]; then
        RESTIC_PASSWORD=$(grep "RESTIC_PASSWORD=" .backrest_secrets | cut -d'=' -f2)
    else
        error "Файл .backrest_secrets не найден"
    fi
    
    export RESTIC_REPOSITORY=".config-backup"
    export RESTIC_PASSWORD="$RESTIC_PASSWORD"
    
    # Проверка через Docker контейнер с restic
    if docker run --rm \
        -v "$(pwd)/.config-backup:/repo" \
        -e RESTIC_REPOSITORY=/repo \
        -e RESTIC_PASSWORD="$RESTIC_PASSWORD" \
        restic/restic:latest \
        snapshots &>/dev/null; then
        
        success "Репозиторий restic корректен"
        
        # Получение информации о снапшотах
        echo ""
        log "=== Информация о снапшотах ==="
        docker run --rm \
            -v "$(pwd)/.config-backup:/repo" \
            -e RESTIC_REPOSITORY=/repo \
            -e RESTIC_PASSWORD="$RESTIC_PASSWORD" \
            restic/restic:latest \
            snapshots --compact
            
        echo ""
        log "=== Статистика репозитория ==="
        docker run --rm \
            -v "$(pwd)/.config-backup:/repo" \
            -e RESTIC_REPOSITORY=/repo \
            -e RESTIC_PASSWORD="$RESTIC_PASSWORD" \
            restic/restic:latest \
            stats --mode raw-data
            
    else
        warning "Не удалось проверить репозиторий restic"
        echo "Возможные причины:"
        echo "1. Репозиторий еще не инициализирован"
        echo "2. Неверный пароль"
        echo "3. Поврежденный репозиторий"
        return 1
    fi
}

# Проверка размера бэкапа
check_backup_size() {
    log "Проверка размера бэкапа..."
    
    if [ -d ".config-backup" ]; then
        BACKUP_SIZE=$(du -sh .config-backup | cut -f1)
        success "Размер директории бэкапа: $BACKUP_SIZE"
        
        # Детальная информация
        echo ""
        log "=== Содержимое директории .config-backup ==="
        ls -la .config-backup/
        
        # Проверка свободного места
        echo ""
        log "=== Использование дискового пространства ==="
        df -h . | head -2
    fi
}

# Проверка последнего бэкапа
check_last_backup() {
    log "Проверка времени последнего бэкапа..."
    
    if [ -d ".config-backup" ]; then
        LAST_MODIFIED=$(find .config-backup -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f1)
        
        if [ -n "$LAST_MODIFIED" ]; then
            LAST_BACKUP_TIME=$(date -d "@$LAST_MODIFIED" "+%Y-%m-%d %H:%M:%S")
            HOURS_AGO=$(( ($(date +%s) - ${LAST_MODIFIED%.*}) / 3600 ))
            
            success "Последний бэкап: $LAST_BACKUP_TIME ($HOURS_AGO часов назад)"
            
            if [ "$HOURS_AGO" -gt 48 ]; then
                warning "Последний бэкап был более 48 часов назад"
            fi
        else
            warning "Не удалось определить время последнего бэкапа"
        fi
    fi
}

# Проверка целостности данных
check_data_integrity() {
    log "Проверка целостности исходных данных..."
    
    # Проверка критических директорий
    directories=("env" "conf" "data/postgres" "data/openwebui" "data/ollama")
    
    for dir in "${directories[@]}"; do
        if [ -d "$dir" ]; then
            SIZE=$(du -sh "$dir" | cut -f1)
            success "✓ $dir ($SIZE)"
        else
            warning "✗ $dir (не найдена)"
        fi
    done
}

# Создание отчета
generate_report() {
    log "Генерация отчета о состоянии бэкапа..."
    
    REPORT_FILE="backup-status-report-$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "=== ОТЧЕТ О СОСТОЯНИИ ЛОКАЛЬНОГО БЭКАПА ERNI-KI ==="
        echo "Дата: $(date)"
        echo "Хост: $(hostname)"
        echo ""
        
        echo "=== ДИРЕКТОРИЯ БЭКАПА ==="
        if [ -d ".config-backup" ]; then
            echo "Статус: Существует"
            echo "Размер: $(du -sh .config-backup | cut -f1)"
            echo "Файлов: $(find .config-backup -type f | wc -l)"
        else
            echo "Статус: Не найдена"
        fi
        echo ""
        
        echo "=== ИСХОДНЫЕ ДАННЫЕ ==="
        for dir in "env" "conf" "data/postgres" "data/openwebui" "data/ollama"; do
            if [ -d "$dir" ]; then
                echo "✓ $dir: $(du -sh "$dir" | cut -f1)"
            else
                echo "✗ $dir: не найдена"
            fi
        done
        echo ""
        
        echo "=== ИСПОЛЬЗОВАНИЕ ДИСКА ==="
        df -h . | head -2
        echo ""
        
        echo "=== СТАТУС BACKREST ==="
        if docker-compose ps backrest | grep -q "Up"; then
            echo "Статус: Запущен"
        else
            echo "Статус: Остановлен"
        fi
        
    } > "$REPORT_FILE"
    
    success "Отчет сохранен в $REPORT_FILE"
}

# Показать справку
show_help() {
    echo "Скрипт проверки локального бэкапа ERNI-KI"
    echo ""
    echo "Использование: $0 [опция]"
    echo ""
    echo "Опции:"
    echo "  --quick     Быстрая проверка (только директория)"
    echo "  --full      Полная проверка с restic"
    echo "  --report    Создать отчет"
    echo "  --help      Показать эту справку"
    echo ""
    echo "Без параметров выполняется стандартная проверка"
}

# Основная функция
main() {
    local mode=${1:-"standard"}
    
    case $mode in
        "--quick")
            log "Быстрая проверка локального бэкапа..."
            check_backup_directory
            check_backup_size
            ;;
        "--full")
            log "Полная проверка локального бэкапа..."
            check_backup_directory && check_with_restic
            check_backup_size
            check_last_backup
            check_data_integrity
            ;;
        "--report")
            log "Создание отчета о состоянии бэкапа..."
            generate_report
            ;;
        "--help")
            show_help
            ;;
        *)
            log "Стандартная проверка локального бэкапа..."
            check_backup_directory
            check_backup_size
            check_last_backup
            check_data_integrity
            ;;
    esac
    
    echo ""
    success "Проверка завершена!"
    
    if [ "$mode" != "--help" ] && [ "$mode" != "--report" ]; then
        echo ""
        log "Дополнительные команды:"
        echo "  $0 --full     # Полная проверка с restic"
        echo "  $0 --report   # Создать детальный отчет"
        echo "  ./scripts/backrest-management.sh status  # Статус Backrest"
    fi
}

# Запуск скрипта
main "$@"
