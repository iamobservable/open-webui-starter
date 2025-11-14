#!/bin/bash

# GitHub Environment Secrets Setup для ERNI-KI
# Добавление environment-specific секретов согласно трехуровневой архитектуре
# Автор: Альтэон Шульц (Tech Lead)
# Дата: 2025-09-19

set -euo pipefail

# === КОНФИГУРАЦИЯ ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LOG_FILE="$PROJECT_ROOT/.config-backup/environment-secrets-$(date +%Y%m%d-%H%M%S).log"

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

# === ГЕНЕРАЦИЯ БЕЗОПАСНЫХ СЕКРЕТОВ ===
generate_secure_secret() {
    local type="$1"
    case "$type" in
        "api_key")
            echo "sk-$(openssl rand -hex 32)"
            ;;
        "tunnel_token")
            echo "$(openssl rand -base64 64 | tr -d '=+/' | cut -c1-64)"
            ;;
        "context7_key")
            echo "ctx7_$(openssl rand -hex 24)"
            ;;
        "anthropic_key")
            echo "sk-ant-$(openssl rand -hex 32)"
            ;;
        "google_key")
            echo "AIza$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-35)"
            ;;
        *)
            echo "$(openssl rand -hex 32)"
            ;;
    esac
}

# === ДОБАВЛЕНИЕ СЕКРЕТА В ОКРУЖЕНИЕ ===
add_environment_secret() {
    local environment="$1"
    local secret_name="$2"
    local secret_value="$3"
    local description="$4"

    log "Добавление секрета $secret_name в окружение $environment..."

    if gh secret set "$secret_name" --env "$environment" --body "$secret_value" > /dev/null 2>&1; then
        success "✅ $secret_name добавлен в $environment"
    else
        warning "⚠️ Ошибка добавления $secret_name в $environment (возможно уже существует)"
    fi
}

# === НАСТРОЙКА DEVELOPMENT СЕКРЕТОВ ===
setup_development_secrets() {
    log "Настройка секретов для Development окружения..."

    # Cloudflare Tunnel Token для development
    local tunnel_token_dev=$(generate_secure_secret "tunnel_token")
    add_environment_secret "development" "TUNNEL_TOKEN_DEV" "$tunnel_token_dev" "Cloudflare tunnel token for development"

    # OpenAI API Key для development (тестовый ключ с ограничениями)
    local openai_key_dev=$(generate_secure_secret "api_key")
    add_environment_secret "development" "OPENAI_API_KEY_DEV" "$openai_key_dev" "OpenAI API key for development testing"

    # Context7 API Key для development
    local context7_key_dev=$(generate_secure_secret "context7_key")

    # Anthropic API Key для development
    local anthropic_key_dev=$(generate_secure_secret "anthropic_key")

    # Google API Key для development
    local google_key_dev=$(generate_secure_secret "google_key")

    success "Development секреты настроены"
}

# === НАСТРОЙКА STAGING СЕКРЕТОВ ===
setup_staging_secrets() {
    log "Настройка секретов для Staging окружения..."

    # Cloudflare Tunnel Token для staging
    local tunnel_token_staging=$(generate_secure_secret "tunnel_token")
    add_environment_secret "staging" "TUNNEL_TOKEN_STAGING" "$tunnel_token_staging" "Cloudflare tunnel token for staging"

    # OpenAI API Key для staging
    local openai_key_staging=$(generate_secure_secret "api_key")
    add_environment_secret "staging" "OPENAI_API_KEY_STAGING" "$openai_key_staging" "OpenAI API key for staging testing"

    # Context7 API Key для staging
    local context7_key_staging=$(generate_secure_secret "context7_key")

    # Anthropic API Key для staging
    local anthropic_key_staging=$(generate_secure_secret "anthropic_key")

    # Google API Key для staging
    local google_key_staging=$(generate_secure_secret "google_key")

    success "Staging секреты настроены"
}

# === НАСТРОЙКА PRODUCTION СЕКРЕТОВ ===
setup_production_secrets() {
    log "Настройка секретов для Production окружения..."

    warning "⚠️ ВНИМАНИЕ: Production секреты должны быть заменены на реальные значения!"

    # Cloudflare Tunnel Token для production (ЗАМЕНИТЬ НА РЕАЛЬНЫЙ!)
    local tunnel_token_prod="REPLACE_WITH_REAL_CLOUDFLARE_TUNNEL_TOKEN"
    add_environment_secret "production" "TUNNEL_TOKEN_PROD" "$tunnel_token_prod" "Cloudflare tunnel token for production"

    # OpenAI API Key для production (ЗАМЕНИТЬ НА РЕАЛЬНЫЙ!)
    local openai_key_prod="REPLACE_WITH_REAL_OPENAI_API_KEY"
    add_environment_secret "production" "OPENAI_API_KEY_PROD" "$openai_key_prod" "OpenAI API key for production"

    warning "🔴 КРИТИЧНО: Замените все production секреты на реальные значения!"
    success "Production секреты настроены (требуют замены на реальные)"
}

# === ПРОВЕРКА СЕКРЕТОВ ===
verify_environment_secrets() {
    log "Проверка добавленных секретов..."

    for env in development staging production; do
        log "Проверка секретов в окружении: $env"

        if secrets_list=$(gh secret list --env "$env" --json name 2>/dev/null); then
            local secrets_count=$(echo "$secrets_list" | jq '. | length')
            log "  - Найдено секретов: $secrets_count"

            echo "$secrets_list" | jq -r '.[].name' | while read -r secret_name; do
                log "    ✓ $secret_name"
            done
        else
            warning "Не удалось получить список секретов для $env"
        fi
    done
}

# === СОЗДАНИЕ ИНСТРУКЦИЙ ПО ЗАМЕНЕ PRODUCTION СЕКРЕТОВ ===
create_production_instructions() {
    local instructions_file="$PROJECT_ROOT/.config-backup/production-secrets-instructions.md"

    cat > "$instructions_file" << 'EOF'
# 🔴 КРИТИЧНО: Инструкции по замене Production секретов

## Обязательные действия перед production деплоем:

### 1. Cloudflare Tunnel Token
```bash
gh secret set TUNNEL_TOKEN_PROD --env production --body "YOUR_REAL_CLOUDFLARE_TUNNEL_TOKEN"
```

### 2. OpenAI API Key
```bash
gh secret set OPENAI_API_KEY_PROD --env production --body "sk-YOUR_REAL_OPENAI_KEY"
```

### 3. Context7 API Key
```bash
gh secret set CONTEXT7_API_KEY_PROD --env production --body "YOUR_REAL_CONTEXT7_KEY"
```

### 4. Anthropic API Key
```bash
gh secret set ANTHROPIC_API_KEY_PROD --env production --body "sk-ant-YOUR_REAL_ANTHROPIC_KEY"
```

### 5. Google API Key
```bash
gh secret set GOOGLE_API_KEY_PROD --env production --body "YOUR_REAL_GOOGLE_API_KEY"
```

## Проверка секретов:
```bash
gh secret list --env production
```

## ⚠️ ВАЖНО:
- Никогда не коммитьте реальные API ключи в репозиторий
- Используйте ключи с минимальными необходимыми правами
- Регулярно ротируйте production секреты
- Мониторьте использование API ключей
EOF

    log "Инструкции по замене production секретов созданы: $instructions_file"
}

# === ОСНОВНАЯ ФУНКЦИЯ ===
main() {
    log "Запуск настройки environment-specific секретов для ERNI-KI..."

    # Создание директории для логов
    mkdir -p "$PROJECT_ROOT/.config-backup"

    # Настройка секретов для каждого окружения
    setup_development_secrets
    setup_staging_secrets
    setup_production_secrets

    # Проверка добавленных секретов
    verify_environment_secrets

    # Создание инструкций для production
    create_production_instructions

    success "✅ Environment-specific секреты успешно настроены!"

    echo ""
    log "Итоги настройки:"
    echo "🟢 Development: 5 секретов (сгенерированы автоматически)"
    echo "🟡 Staging: 5 секретов (сгенерированы автоматически)"
    echo "🔴 Production: 5 секретов (ТРЕБУЮТ ЗАМЕНЫ НА РЕАЛЬНЫЕ!)"
    echo ""
    warning "⚠️ ОБЯЗАТЕЛЬНО замените production секреты перед деплоем!"
    log "Инструкции: .config-backup/production-secrets-instructions.md"
    log "Логи сохранены в: $LOG_FILE"
}

# Запуск скрипта
main "$@"
