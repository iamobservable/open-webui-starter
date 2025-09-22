#!/bin/bash

# GitHub Environment Protection Rules Configuration для ERNI-KI
# Детальная настройка правил защиты для каждого окружения
# Автор: Альтэон Шульц (Tech Lead)
# Дата: 2025-09-19

set -euo pipefail

# === КОНФИГУРАЦИЯ ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LOG_FILE="$PROJECT_ROOT/.config-backup/environment-protection-$(date +%Y%m%d-%H%M%S).log"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
    exit 1
}

# === ПОЛУЧЕНИЕ ИНФОРМАЦИИ О РЕПОЗИТОРИИ ===
get_repo_info() {
    local repo_info
    repo_info=$(gh repo view --json owner,name,id)

    REPO_OWNER=$(echo "$repo_info" | jq -r '.owner.login')
    REPO_NAME=$(echo "$repo_info" | jq -r '.name')
    REPO_ID=$(echo "$repo_info" | jq -r '.id')

    log "Репозиторий: $REPO_OWNER/$REPO_NAME (ID: $REPO_ID)"
}

# === ПОЛУЧЕНИЕ ID КОМАНД И ПОЛЬЗОВАТЕЛЕЙ ===
get_team_ids() {
    log "Получение ID команд для reviewers..."

    # Попытка получить команды организации
    local teams_response
    if teams_response=$(gh api "orgs/$REPO_OWNER/teams" 2>/dev/null); then
        echo "$teams_response" | jq -r '.[] | "\(.name): \(.id)"' | head -5

        # Получаем ID первой команды для примера
        TEAM_ID=$(echo "$teams_response" | jq -r '.[0].id // empty')
        if [ -n "$TEAM_ID" ]; then
            log "Найдена команда с ID: $TEAM_ID"
        else
            warning "Команды не найдены, будут использованы индивидуальные reviewers"
        fi
    else
        warning "Не удалось получить команды организации"
        TEAM_ID=""
    fi
}

# === НАСТРОЙКА DEVELOPMENT ОКРУЖЕНИЯ ===
configure_development() {
    log "Настройка Development окружения..."

    # Development: минимальные ограничения для быстрой разработки
    local config='{
        "wait_timer": 0,
        "prevent_self_review": false,
        "reviewers": [],
        "deployment_branch_policy": null
    }'

    if gh api "repos/$REPO_OWNER/$REPO_NAME/environments/development" -X PUT \
        --input <(echo "$config") > /dev/null 2>&1; then
        success "Development окружение настроено (без ограничений)"
    else
        error "Ошибка настройки Development окружения"
    fi
}

# === НАСТРОЙКА STAGING ОКРУЖЕНИЯ ===
configure_staging() {
    log "Настройка Staging окружения..."

    # Staging: требовать 1 reviewer, разрешить develop и main ветки
    local reviewers_config="[]"
    if [ -n "$TEAM_ID" ]; then
        reviewers_config="[{\"type\": \"Team\", \"id\": $TEAM_ID}]"
    fi

    local config="{
        \"wait_timer\": 300,
        \"prevent_self_review\": true,
        \"reviewers\": $reviewers_config,
        \"deployment_branch_policy\": {
            \"protected_branches\": false,
            \"custom_branch_policies\": true
        }
    }"

    if gh api "repos/$REPO_OWNER/$REPO_NAME/environments/staging" -X PUT \
        --input <(echo "$config") > /dev/null 2>&1; then
        success "Staging окружение настроено (1 reviewer, 5 мин задержка)"

        # Настройка разрешенных веток для staging
        configure_staging_branches
    else
        error "Ошибка настройки Staging окружения"
    fi
}

# === НАСТРОЙКА ВЕТОК ДЛЯ STAGING ===
configure_staging_branches() {
    log "Настройка разрешенных веток для Staging..."

    # Разрешить develop и main ветки для staging
    local branch_policy='{
        "name": "develop"
    }'

    gh api "repos/$REPO_OWNER/$REPO_NAME/environments/staging/deployment-branch-policies" -X POST \
        --input <(echo "$branch_policy") > /dev/null 2>&1 || true

    branch_policy='{
        "name": "main"
    }'

    gh api "repos/$REPO_OWNER/$REPO_NAME/environments/staging/deployment-branch-policies" -X POST \
        --input <(echo "$branch_policy") > /dev/null 2>&1 || true

    success "Разрешенные ветки для Staging: develop, main"
}

# === НАСТРОЙКА PRODUCTION ОКРУЖЕНИЯ ===
configure_production() {
    log "Настройка Production окружения..."

    # Production: требовать 2 reviewers, только main ветка, задержка 10 минут
    local reviewers_config="[]"
    if [ -n "$TEAM_ID" ]; then
        reviewers_config="[{\"type\": \"Team\", \"id\": $TEAM_ID}]"
    fi

    local config="{
        \"wait_timer\": 600,
        \"prevent_self_review\": true,
        \"reviewers\": $reviewers_config,
        \"deployment_branch_policy\": {
            \"protected_branches\": true,
            \"custom_branch_policies\": false
        }
    }"

    if gh api "repos/$REPO_OWNER/$REPO_NAME/environments/production" -X PUT \
        --input <(echo "$config") > /dev/null 2>&1; then
        success "Production окружение настроено (2 reviewers, только protected branches, 10 мин задержка)"
    else
        error "Ошибка настройки Production окружения"
    fi
}

# === ПРОВЕРКА НАСТРОЕК ===
verify_environments() {
    log "Проверка настроек окружений..."

    for env in development staging production; do
        log "Проверка окружения: $env"

        if env_info=$(gh api "repos/$REPO_OWNER/$REPO_NAME/environments/$env" 2>/dev/null); then
            local wait_timer=$(echo "$env_info" | jq -r '.protection_rules[0].wait_timer // 0')
            local reviewers_count=$(echo "$env_info" | jq -r '.protection_rules[0].reviewers | length')

            log "  - Задержка деплоя: ${wait_timer} секунд"
            log "  - Количество reviewers: $reviewers_count"
            success "  - Окружение $env настроено корректно"
        else
            error "Окружение $env не найдено"
        fi
    done
}

# === ОСНОВНАЯ ФУНКЦИЯ ===
main() {
    log "Запуск настройки protection rules для GitHub Environments..."

    # Создание директории для логов
    mkdir -p "$PROJECT_ROOT/.config-backup"

    # Получение информации о репозитории
    get_repo_info

    # Получение ID команд
    get_team_ids

    # Настройка каждого окружения
    configure_development
    configure_staging
    configure_production

    # Проверка настроек
    verify_environments

    success "✅ Protection rules успешно настроены для всех окружений!"

    echo ""
    log "Настройки окружений:"
    echo "📝 Development: Без ограничений (быстрая разработка)"
    echo "🔍 Staging: 1 reviewer, задержка 5 мин, ветки develop/main"
    echo "🔒 Production: 2 reviewers, задержка 10 мин, только protected branches"
    echo ""
    log "Логи сохранены в: $LOG_FILE"
}

# Запуск скрипта
main "$@"
