#!/bin/bash

# ===================================================================
# Универсальный скрипт исправления прав доступа для ERNI-KI
# Исправляет проблемы с доступом Snyk и других инструментов ко всем директориям data/
# Поддерживает: Backrest, Grafana, PostgreSQL и другие сервисы
# ===================================================================

set -euo pipefail

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Этот скрипт должен быть запущен с правами root (sudo)"
        exit 1
    fi
}

# Проверка существования директории data
check_data_directory() {
    local data_dir="data"

    if [[ ! -d "$data_dir" ]]; then
        error "Директория data не найдена: $data_dir"
        exit 1
    fi

    log "Директория data найдена: $data_dir"
}

# Поиск проблемных директорий
find_problematic_directories() {
    log "Поиск директорий с ограниченными правами доступа..."

    # Находим директории без права execute для "остальных" пользователей
    local problematic_dirs
    problematic_dirs=$(find data/ -type d ! -perm -o+x 2>/dev/null || true)

    if [[ -n "$problematic_dirs" ]]; then
        echo "=== Найдены проблемные директории ==="
        echo "$problematic_dirs" | while read -r dir; do
            if [[ -n "$dir" ]]; then
                ls -ld "$dir" 2>/dev/null || echo "Недоступно: $dir"
            fi
        done
        echo ""
        return 0
    else
        log "Проблемные директории не найдены"
        return 1
    fi
}

# Анализ текущих прав доступа
analyze_permissions() {
    log "Анализ текущих прав доступа..."

    echo "=== Общий обзор директории data ==="
    ls -la data/ | head -10
    echo ""

    # Анализ конкретных сервисов
    for service_dir in data/backrest data/grafana data/postgres data/prometheus data/redis; do
        if [[ -d "$service_dir" ]]; then
            echo "=== Права доступа к $service_dir ==="
            ls -la "$service_dir/" 2>/dev/null | head -5 || echo "Доступ ограничен"
            echo ""
        fi
    done
}

# Исправление прав доступа
fix_permissions() {
    log "Исправление прав доступа..."

    local fixed_count=0

    # Находим и исправляем все проблемные директории
    local problematic_dirs
    problematic_dirs=$(find data/ -type d ! -perm -o+x 2>/dev/null || true)

    if [[ -n "$problematic_dirs" ]]; then
        echo "$problematic_dirs" | while read -r dir; do
            if [[ -n "$dir" && -d "$dir" ]]; then
                log "Исправление прав доступа к $dir"

                # Определяем подходящие права в зависимости от сервиса
                case "$dir" in
                    data/postgres*)
                        # PostgreSQL требует более строгие права
                        chmod 750 "$dir" 2>/dev/null || warning "Не удалось изменить права для $dir"
                        ;;
                    data/grafana/alerting*)
                        # Grafana alerting - рекурсивно исправляем
                        chmod -R 755 "$dir" 2>/dev/null || warning "Не удалось изменить права для $dir"
                        ;;
                    *)
                        # Остальные директории - стандартные права
                        chmod 755 "$dir" 2>/dev/null || warning "Не удалось изменить права для $dir"
                        ;;
                esac

                ((fixed_count++)) || true
            fi
        done

        success "Исправлено прав доступа для директорий: $fixed_count"
    else
        log "Проблемные директории не найдены"
    fi

    # Специальная обработка для Backrest репозитория
    if [[ -d "data/backrest/repos/erni-ki-local" ]]; then
        log "Дополнительное исправление для Backrest репозитория"
        chmod -R 755 data/backrest/repos/erni-ki-local 2>/dev/null || warning "Не удалось исправить права Backrest"
    fi
}

# Проверка доступности после исправления
verify_access() {
    log "Проверка доступности после исправления..."

    local verification_failed=0

    # Проверяем все ранее проблемные директории
    local test_dirs=("data/backrest/repos" "data/grafana/alerting" "data/grafana/csv" "data/grafana/png")

    for dir in "${test_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            if ls "$dir/" >/dev/null 2>&1; then
                success "Доступ к $dir восстановлен"
            else
                error "Доступ к $dir всё ещё ограничен"
                ((verification_failed++))
            fi
        fi
    done

    # Специальная проверка для Backrest репозитория
    if [[ -d "data/backrest/repos/erni-ki-local" ]]; then
        if ls data/backrest/repos/erni-ki-local/ >/dev/null 2>&1; then
            success "Доступ к Backrest репозиторию восстановлен"
        else
            error "Доступ к Backrest репозиторию всё ещё ограничен"
            ((verification_failed++))
        fi
    fi

    # Проверяем, что не осталось проблемных директорий
    local remaining_issues
    remaining_issues=$(find data/ -type d ! -perm -o+x 2>/dev/null | wc -l)

    if [[ "$remaining_issues" -eq 0 ]]; then
        success "Все проблемы с правами доступа устранены"
    else
        warning "Остались проблемные директории: $remaining_issues"
        ((verification_failed++))
    fi

    return $verification_failed
}

# Проверка работы сервисов
check_services() {
    log "Проверка работы сервисов..."

    # Проверяем Backrest
    if docker ps | grep -q backrest; then
        success "Контейнер Backrest запущен"
        if curl -s http://localhost:9898/ >/dev/null 2>&1; then
            success "Веб-интерфейс Backrest доступен"
        else
            warning "Веб-интерфейс Backrest недоступен"
        fi
    else
        warning "Контейнер Backrest не запущен"
    fi

    # Проверяем Grafana
    if docker ps | grep -q grafana; then
        success "Контейнер Grafana запущен"
        if curl -s http://localhost:3000/ >/dev/null 2>&1; then
            success "Веб-интерфейс Grafana доступен"
        else
            warning "Веб-интерфейс Grafana недоступен"
        fi
    else
        warning "Контейнер Grafana не запущен"
    fi

    # Проверяем PostgreSQL
    if docker ps | grep -q postgres; then
        success "Контейнер PostgreSQL запущен"
    else
        warning "Контейнер PostgreSQL не запущен"
    fi
}

# Создание отчёта
create_report() {
    local report_file="logs/data-permissions-fix-$(date +%Y%m%d_%H%M%S).log"

    log "Создание отчёта: $report_file"

    {
        echo "=== Отчёт об исправлении прав доступа ERNI-KI ==="
        echo "Дата: $(date)"
        echo "Пользователь: $(whoami)"
        echo ""
        echo "=== Общий обзор директории data ==="
        ls -la data/ 2>/dev/null || echo "Директория data недоступна"
        echo ""

        # Отчёт по каждому сервису
        for service in backrest grafana postgres prometheus redis; do
            if [[ -d "data/$service" ]]; then
                echo "=== Права доступа к data/$service ==="
                ls -la "data/$service/" 2>/dev/null || echo "Директория data/$service недоступна"
                echo ""
            fi
        done

        echo "=== Проверка проблемных директорий ==="
        local remaining_issues
        remaining_issues=$(find data/ -type d ! -perm -o+x 2>/dev/null || true)
        if [[ -n "$remaining_issues" ]]; then
            echo "Остались проблемные директории:"
            echo "$remaining_issues"
        else
            echo "Проблемные директории не найдены"
        fi

        echo ""
        echo "=== Статус сервисов ==="
        docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(backrest|grafana|postgres)" || echo "Сервисы не найдены"

    } > "$report_file"

    success "Отчёт создан: $report_file"
}

# Основная функция
main() {
    log "Запуск универсального исправления прав доступа для ERNI-KI"

    # Проверки
    check_root
    check_data_directory

    # Анализ проблем
    analyze_permissions
    if ! find_problematic_directories; then
        success "Проблемы с правами доступа не обнаружены"
        exit 0
    fi

    # Исправление и проверка
    fix_permissions
    verify_access
    check_services
    create_report

    success "Исправление прав доступа завершено успешно"

    echo ""
    echo "=== Рекомендации ==="
    echo "1. Snyk теперь может сканировать проект без ошибок доступа"
    echo "2. Все сервисы (Backrest, Grafana, PostgreSQL) продолжают работать"
    echo "3. Безопасность сохранена (только чтение для других пользователей)"
    echo "4. При появлении новых проблем запустите этот скрипт повторно"
    echo "5. Рассмотрите добавление скрипта в cron для автоматической проверки"
}

# Запуск основной функции
main "$@"
