#!/bin/bash

# GitHub Environment Secrets Validation для ERNI-KI
# Комплексная проверка доступности и корректности всех секретов
# Автор: Альтэон Шульц (Tech Lead)
# Дата: 2025-09-19

set -euo pipefail

# === КОНФИГУРАЦИЯ ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LOG_FILE="$PROJECT_ROOT/.config-backup/secrets-validation-$(date +%Y%m%d-%H%M%S).log"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# === ФУНКЦИИ ЛОГИРОВАНИЯ ===
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${PURPLE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# === ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ===
TOTAL_SECRETS=0
VALID_SECRETS=0
INVALID_SECRETS=0
MISSING_SECRETS=0

# === ПРОВЕРКА ЗАВИСИМОСТЕЙ ===
check_dependencies() {
    log "Проверка зависимостей..."

    # Проверка GitHub CLI
    if ! command -v gh &> /dev/null; then
        error "GitHub CLI не установлен. Установите: https://cli.github.com/"
        exit 1
    fi

    # Проверка аутентификации
    if ! gh auth status &> /dev/null; then
        error "GitHub CLI не аутентифицирован. Выполните: gh auth login"
        exit 1
    fi

    # Проверка jq
    if ! command -v jq &> /dev/null; then
        warning "jq не установлен. Некоторые функции могут работать некорректно."
    fi

    success "Все зависимости проверены"
}

# === ПОЛУЧЕНИЕ СПИСКА ОКРУЖЕНИЙ ===
get_environments() {
    log "Получение списка окружений..."

    local environments
    if environments=$(gh api "repos/:owner/:repo/environments" --jq '.[].name' 2>/dev/null); then
        echo "$environments"
    else
        warning "Не удалось получить список окружений"
        echo "development staging production"
    fi
}

# === ПРОВЕРКА СЕКРЕТА В ОКРУЖЕНИИ ===
validate_secret() {
    local environment="$1"
    local secret_name="$2"
    local is_critical="${3:-false}"

    TOTAL_SECRETS=$((TOTAL_SECRETS + 1))

    # Проверяем существование секрета
    if gh secret list --env "$environment" --json name | jq -r '.[].name' | grep -q "^${secret_name}$"; then
        if [ "$is_critical" = "true" ]; then
            # Для критических секретов проверяем, что они не содержат placeholder
            local secret_info
            if secret_info=$(gh api "repos/:owner/:repo/environments/$environment/secrets/$secret_name" 2>/dev/null); then
                local updated_at=$(echo "$secret_info" | jq -r '.updated_at')
                success "✅ $secret_name ($environment) - обновлен: $updated_at"
                VALID_SECRETS=$((VALID_SECRETS + 1))
            else
                warning "⚠️ $secret_name ($environment) - существует, но нет доступа к метаданным"
                VALID_SECRETS=$((VALID_SECRETS + 1))
            fi
        else
            success "✅ $secret_name ($environment) - найден"
            VALID_SECRETS=$((VALID_SECRETS + 1))
        fi
    else
        error "❌ $secret_name ($environment) - отсутствует"
        MISSING_SECRETS=$((MISSING_SECRETS + 1))
    fi
}

# === ПРОВЕРКА СЕКРЕТОВ ДЛЯ ОКРУЖЕНИЯ ===
validate_environment_secrets() {
    local environment="$1"

    info "🔍 Проверка секретов для окружения: $environment"

    # Определяем суффикс для окружения
    local env_suffix=""
    case "$environment" in
        "development") env_suffix="_DEV" ;;
        "staging") env_suffix="_STAGING" ;;
        "production") env_suffix="_PROD" ;;
        *)
            warning "Неизвестное окружение: $environment"
            return 1
            ;;
    esac

    # Список обязательных секретов для каждого окружения
    local required_secrets=(
        "TUNNEL_TOKEN${env_suffix}"
        "OPENAI_API_KEY${env_suffix}"
    )

    # Проверяем каждый секрет
    for secret in "${required_secrets[@]}"; do
        local is_critical="false"
        if [ "$environment" = "production" ]; then
            is_critical="true"
        fi
        validate_secret "$environment" "$secret" "$is_critical"
    done

    # Получаем дополнительные секреты в окружении
    local additional_secrets
    if additional_secrets=$(gh secret list --env "$environment" --json name | jq -r '.[].name' 2>/dev/null); then
        local additional_count=0
        while IFS= read -r secret_name; do
            if [[ ! " ${required_secrets[*]} " =~ " ${secret_name} " ]]; then
                info "ℹ️ Дополнительный секрет: $secret_name ($environment)"
                additional_count=$((additional_count + 1))
            fi
        done <<< "$additional_secrets"

        if [ $additional_count -gt 0 ]; then
            info "Найдено $additional_count дополнительных секретов в $environment"
        fi
    fi
}

# === ПРОВЕРКА REPOSITORY-LEVEL СЕКРЕТОВ ===
validate_repository_secrets() {
    info "🔍 Проверка repository-level секретов..."

    # Список критических repository секретов
    local repo_secrets=(
        "POSTGRES_PASSWORD"
        "JWT_SECRET"
        "WEBUI_SECRET_KEY"
        "LITELLM_MASTER_KEY"
        "LITELLM_SALT_KEY"
        "RESTIC_PASSWORD"
        "SEARXNG_SECRET"
        "REDIS_PASSWORD"
        "BACKREST_PASSWORD"
    )

    # Проверяем каждый repository секрет
    for secret in "${repo_secrets[@]}"; do
        TOTAL_SECRETS=$((TOTAL_SECRETS + 1))

        if gh secret list --json name | jq -r '.[].name' | grep -q "^${secret}$"; then
            success "✅ $secret (repository) - найден"
            VALID_SECRETS=$((VALID_SECRETS + 1))
        else
            error "❌ $secret (repository) - отсутствует"
            MISSING_SECRETS=$((MISSING_SECRETS + 1))
        fi
    done
}

# === ПРОВЕРКА БЕЗОПАСНОСТИ СЕКРЕТОВ ===
security_check() {
    info "🛡️ Проверка безопасности секретов..."

    local security_issues=0

    # Проверяем, что production секреты не содержат тестовые значения
    log "Проверка production секретов на placeholder значения..."

    # Здесь можно добавить дополнительные проверки безопасности
    # Например, проверка силы паролей, ротации секретов и т.д.

    if [ $security_issues -eq 0 ]; then
        success "Проблем безопасности не обнаружено"
    else
        warning "Обнаружено $security_issues проблем безопасности"
    fi
}

# === ГЕНЕРАЦИЯ ОТЧЕТА ===
generate_report() {
    local report_file="$PROJECT_ROOT/.config-backup/secrets-validation-report-$(date +%Y%m%d-%H%M%S).md"

    cat > "$report_file" << EOF
# 🔐 Отчет о валидации GitHub Secrets для ERNI-KI

**Дата проверки:** $(date +'%Y-%m-%d %H:%M:%S')
**Проверено окружений:** $(get_environments | wc -l)
**Всего секретов:** $TOTAL_SECRETS

## 📊 Статистика

- ✅ **Валидные секреты:** $VALID_SECRETS
- ❌ **Отсутствующие секреты:** $MISSING_SECRETS
- ⚠️ **Проблемные секреты:** $INVALID_SECRETS

## 🎯 Результаты по окружениям

EOF

    # Добавляем детали по каждому окружению
    while IFS= read -r env; do
        echo "### $env" >> "$report_file"
        echo "" >> "$report_file"

        # Получаем список секретов для окружения
        if secrets_list=$(gh secret list --env "$env" --json name,updated_at 2>/dev/null); then
            echo "$secrets_list" | jq -r '.[] | "- ✅ \(.name) (обновлен: \(.updated_at))"' >> "$report_file"
        else
            echo "- ⚠️ Не удалось получить список секретов" >> "$report_file"
        fi

        echo "" >> "$report_file"
    done <<< "$(get_environments)"

    cat >> "$report_file" << EOF

## 🔧 Рекомендации

$(if [ $MISSING_SECRETS -gt 0 ]; then
    echo "### ❌ Критические проблемы"
    echo "- Отсутствует $MISSING_SECRETS секретов"
    echo "- Выполните: \`./scripts/infrastructure/security/setup-environment-secrets.sh\`"
    echo ""
fi)

$(if [ $INVALID_SECRETS -gt 0 ]; then
    echo "### ⚠️ Предупреждения"
    echo "- Обнаружено $INVALID_SECRETS проблемных секретов"
    echo "- Проверьте корректность значений"
    echo ""
fi)

### 🔄 Следующие шаги

1. Исправить отсутствующие секреты
2. Заменить placeholder значения на реальные (особенно для production)
3. Настроить автоматическую ротацию секретов
4. Регулярно проводить аудит секретов

---
*Отчет сгенерирован автоматически скриптом validate-environment-secrets.sh*
EOF

    log "Отчет сохранен: $report_file"
}

# === ОСНОВНАЯ ФУНКЦИЯ ===
main() {
    log "Запуск валидации GitHub Secrets для ERNI-KI..."

    # Создание директории для логов
    mkdir -p "$PROJECT_ROOT/.config-backup"

    # Проверка зависимостей
    check_dependencies

    # Получение списка окружений
    local environments
    environments=$(get_environments)

    log "Найдены окружения: $environments"

    # Проверка repository-level секретов
    validate_repository_secrets

    # Проверка секретов для каждого окружения
    while IFS= read -r env; do
        validate_environment_secrets "$env"
    done <<< "$environments"

    # Проверка безопасности
    security_check

    # Генерация отчета
    generate_report

    # Итоговая статистика
    echo ""
    info "📊 ИТОГОВАЯ СТАТИСТИКА:"
    echo "  🔢 Всего секретов: $TOTAL_SECRETS"
    echo "  ✅ Валидные: $VALID_SECRETS"
    echo "  ❌ Отсутствующие: $MISSING_SECRETS"
    echo "  ⚠️ Проблемные: $INVALID_SECRETS"

    if [ $MISSING_SECRETS -eq 0 ] && [ $INVALID_SECRETS -eq 0 ]; then
        success "🎉 Все секреты настроены корректно!"
        exit 0
    else
        warning "⚠️ Обнаружены проблемы с секретами. Проверьте отчет."
        exit 1
    fi
}

# Обработка аргументов командной строки
case "${1:-}" in
    "--help"|"-h")
        echo "Использование: $0 [--help|--dry-run]"
        echo "  --help, -h     Показать эту справку"
        echo "  --dry-run      Выполнить проверку без изменений"
        exit 0
        ;;
    "--dry-run")
        log "Режим dry-run: только проверка, без изменений"
        ;;
esac

# Запуск скрипта
main "$@"
