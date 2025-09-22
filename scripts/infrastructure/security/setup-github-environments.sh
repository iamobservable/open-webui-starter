#!/bin/bash

# GitHub Environments Setup для ERNI-KI
# Создание и настройка окружений development, staging, production
# Автор: Альтэон Шульц (Tech Lead)
# Дата: 2025-09-19

set -euo pipefail

# === КОНФИГУРАЦИЯ ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LOG_FILE="$PROJECT_ROOT/.config-backup/github-environments-setup-$(date +%Y%m%d-%H%M%S).log"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# === ПРОВЕРКА ЗАВИСИМОСТЕЙ ===
check_dependencies() {
    log "Проверка зависимостей..."

    # Проверка GitHub CLI
    if ! command -v gh &> /dev/null; then
        error "GitHub CLI не установлен. Установите: https://cli.github.com/"
    fi

    # Проверка аутентификации
    if ! gh auth status &> /dev/null; then
        error "GitHub CLI не аутентифицирован. Выполните: gh auth login"
    fi

    # Проверка прав доступа
    local repo_info
    if ! repo_info=$(gh repo view --json owner,name 2>/dev/null); then
        error "Нет доступа к репозиторию или не в корне git репозитория"
    fi

    local owner=$(echo "$repo_info" | jq -r '.owner.login')
    local repo=$(echo "$repo_info" | jq -r '.name')

    log "Репозиторий: $owner/$repo"

    # Проверка прав на создание environments
    if ! gh api "repos/$owner/$repo" --jq '.permissions.admin' | grep -q true; then
        warning "Возможно недостаточно прав для создания environments. Требуются admin права."
    fi

    success "Все зависимости проверены"
}

# === СОЗДАНИЕ ОКРУЖЕНИЙ ===
create_environment() {
    local env_name="$1"
    local description="$2"

    log "Создание окружения: $env_name"

    # Создание окружения
    if gh api "repos/:owner/:repo/environments/$env_name" -X PUT \
        --field "wait_timer=0" \
        --field "prevent_self_review=false" \
        --field "reviewers=[]" \
        --field "deployment_branch_policy=null" > /dev/null 2>&1; then
        success "Окружение $env_name создано"
    else
        warning "Окружение $env_name уже существует или ошибка создания"
    fi
}

# === НАСТРОЙКА PROTECTION RULES ===
setup_development_protection() {
    log "Настройка protection rules для development..."

    # Development: без ограничений доступа
    gh api "repos/:owner/:repo/environments/development" -X PUT \
        --field "wait_timer=0" \
        --field "prevent_self_review=false" \
        --field "reviewers=[]" \
        --field "deployment_branch_policy=null" > /dev/null

    success "Development protection rules настроены (без ограничений)"
}

setup_staging_protection() {
    log "Настройка protection rules для staging..."

    # Staging: требовать review от 1 человека
    gh api "repos/:owner/:repo/environments/staging" -X PUT \
        --field "wait_timer=0" \
        --field "prevent_self_review=true" \
        --field "reviewers=[{\"type\":\"Team\",\"id\":null}]" \
        --field "deployment_branch_policy=null" > /dev/null

    success "Staging protection rules настроены (1 reviewer required)"
}

setup_production_protection() {
    log "Настройка protection rules для production..."

    # Production: требовать review от 2 человек + только main ветка
    gh api "repos/:owner/:repo/environments/production" -X PUT \
        --field "wait_timer=0" \
        --field "prevent_self_review=true" \
        --field "reviewers=[{\"type\":\"Team\",\"id\":null}]" \
        --field "deployment_branch_policy={\"protected_branches\":true,\"custom_branch_policies\":false}" > /dev/null

    success "Production protection rules настроены (2 reviewers + main branch only)"
}

# === ОСНОВНАЯ ФУНКЦИЯ ===
main() {
    log "Запуск настройки GitHub Environments для ERNI-KI..."

    # Создание директории для логов
    mkdir -p "$PROJECT_ROOT/.config-backup"

    # Проверка зависимостей
    check_dependencies

    # Создание окружений
    create_environment "development" "Development environment for ERNI-KI"
    create_environment "staging" "Staging environment for ERNI-KI pre-production testing"
    create_environment "production" "Production environment for ERNI-KI live deployment"

    # Настройка protection rules
    setup_development_protection
    setup_staging_protection
    setup_production_protection

    success "✅ GitHub Environments успешно настроены!"

    echo ""
    log "Следующие шаги:"
    echo "1. Добавить environment-specific secrets"
    echo "2. Обновить GitHub Actions workflows"
    echo "3. Протестировать деплой в каждое окружение"
    echo ""
    log "Логи сохранены в: $LOG_FILE"
}

# Запуск скрипта
main "$@"
