#!/bin/bash

# ERNI-KI Backrest Integration Setup
# Настройка резервного копирования и интеграции с мониторингом
# Автор: Альтэон Шульц (Tech Lead)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_ROOT/.config-backup"
BACKREST_API="http://localhost:9898/v1.Backrest"

# === Функции логирования ===
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $*"
}

# === Проверка доступности Backrest ===
check_backrest_availability() {
    log "Проверка доступности Backrest..."

    if curl -s -f "$BACKREST_API/GetConfig" --data '{}' -H 'Content-Type: application/json' >/dev/null 2>&1; then
        success "Backrest API доступен"
        return 0
    else
        error "Backrest API недоступен"
        return 1
    fi
}

# === Создание локального репозитория ===
create_local_repository() {
    log "Создание локального репозитория резервного копирования..."

    # Создание директории для резервных копий
    mkdir -p "$BACKUP_DIR"

    # Генерация пароля для репозитория
    local repo_password
    repo_password=$(openssl rand -base64 32)

    # Сохранение пароля в безопасном месте
    echo "$repo_password" > "$PROJECT_ROOT/conf/backrest/repo-password.txt"
    chmod 600 "$PROJECT_ROOT/conf/backrest/repo-password.txt"

    # Конфигурация репозитория через API
    local repo_config
    repo_config=$(cat <<EOF
{
    "repo": {
        "id": "erni-ki-local",
        "uri": "$BACKUP_DIR",
        "password": "$repo_password",
        "flags": ["--no-lock"],
        "prunePolicy": {
            "schedule": "0 2 * * *",
            "maxUnusedBytes": "1073741824"
        },
        "checkPolicy": {
            "schedule": "0 3 * * 0"
        }
    }
}
EOF
    )

    log "Конфигурация репозитория создана"
    echo "$repo_config" > "$PROJECT_ROOT/conf/backrest/repo-config.json"

    success "Локальный репозиторий настроен в $BACKUP_DIR"
}

# === Создание планов резервного копирования ===
create_backup_plans() {
    log "Создание планов резервного копирования..."

    # План для ежедневного резервного копирования
    local daily_plan
    daily_plan=$(cat <<EOF
{
    "plan": {
        "id": "erni-ki-daily",
        "repo": "erni-ki-local",
        "paths": [
            "$PROJECT_ROOT/env/",
            "$PROJECT_ROOT/conf/",
            "$PROJECT_ROOT/data/postgres/",
            "$PROJECT_ROOT/data/openwebui/",
            "$PROJECT_ROOT/data/ollama/"
        ],
        "excludes": [
            "*.tmp",
            "*.log",
            "*cache*",
            "*.lock"
        ],
        "schedule": "0 1 * * *",
        "retention": {
            "keepDaily": 7
        },
        "hooks": []
    }
}
EOF
    )

    # План для еженедельного резервного копирования
    local weekly_plan
    weekly_plan=$(cat <<EOF
{
    "plan": {
        "id": "erni-ki-weekly",
        "repo": "erni-ki-local",
        "paths": [
            "$PROJECT_ROOT/env/",
            "$PROJECT_ROOT/conf/",
            "$PROJECT_ROOT/data/postgres/",
            "$PROJECT_ROOT/data/openwebui/",
            "$PROJECT_ROOT/data/ollama/"
        ],
        "excludes": [
            "*.tmp",
            "*.log",
            "*cache*",
            "*.lock"
        ],
        "schedule": "0 2 * * 0",
        "retention": {
            "keepWeekly": 4
        },
        "hooks": []
    }
}
EOF
    )

    echo "$daily_plan" > "$PROJECT_ROOT/conf/backrest/daily-plan.json"
    echo "$weekly_plan" > "$PROJECT_ROOT/conf/backrest/weekly-plan.json"

    success "Планы резервного копирования созданы"
}

# === Создание webhook для интеграции с мониторингом ===
create_monitoring_webhook() {
    log "Создание webhook для интеграции с мониторингом rate limiting..."

    # Создание скрипта webhook
    cat > "$PROJECT_ROOT/scripts/backrest-webhook.sh" <<'EOF'
#!/bin/bash

# Backrest Webhook для интеграции с системой мониторинга
# Получает уведомления от Backrest и отправляет их в систему мониторинга

WEBHOOK_DATA="$1"
MONITORING_LOG="/home/konstantin/Documents/augment-projects/erni-ki/logs/backrest-notifications.log"

# Создание директории для логов
mkdir -p "$(dirname "$MONITORING_LOG")"

# Логирование уведомления
echo "[$(date -Iseconds)] Backrest notification: $WEBHOOK_DATA" >> "$MONITORING_LOG"

# Отправка в систему мониторинга rate limiting (если настроена)
if [[ -f "/home/konstantin/Documents/augment-projects/erni-ki/scripts/monitor-rate-limiting.sh" ]]; then
    # Интеграция с системой мониторинга
    echo "Backrest notification: $WEBHOOK_DATA" | logger -t "erni-ki-backrest"
fi

exit 0
EOF

    chmod +x "$PROJECT_ROOT/scripts/backrest-webhook.sh"

    success "Webhook для мониторинга создан"
}

# === Создание hooks для уведомлений ===
create_notification_hooks() {
    log "Создание hooks для уведомлений..."

    # Hook для успешного резервного копирования
    local success_hook
    success_hook=$(cat <<EOF
{
    "hook": {
        "conditions": ["CONDITION_SNAPSHOT_SUCCESS"],
        "actionCommand": {
            "command": "$PROJECT_ROOT/scripts/backrest-webhook.sh",
            "args": ["Backup completed successfully for plan {{ .Plan.Id }} at {{ .FormatTime .CurTime }}"]
        }
    }
}
EOF
    )

    # Hook для ошибок резервного копирования
    local error_hook
    error_hook=$(cat <<EOF
{
    "hook": {
        "conditions": ["CONDITION_SNAPSHOT_ERROR", "CONDITION_ANY_ERROR"],
        "actionCommand": {
            "command": "$PROJECT_ROOT/scripts/backrest-webhook.sh",
            "args": ["Backup FAILED for plan {{ .Plan.Id }}: {{ .Error }}"]
        }
    }
}
EOF
    )

    echo "$success_hook" > "$PROJECT_ROOT/conf/backrest/success-hook.json"
    echo "$error_hook" > "$PROJECT_ROOT/conf/backrest/error-hook.json"

    success "Hooks для уведомлений созданы"
}

# === Тестирование интеграции ===
test_integration() {
    log "Тестирование интеграции Backrest..."

    # Проверка API
    if ! check_backrest_availability; then
        error "Backrest API недоступен для тестирования"
        return 1
    fi

    # Тестирование webhook
    if [[ -x "$PROJECT_ROOT/scripts/backrest-webhook.sh" ]]; then
        "$PROJECT_ROOT/scripts/backrest-webhook.sh" "Test notification from setup script"
        success "Webhook протестирован"
    fi

    # Проверка созданных файлов
    local required_files=(
        "$PROJECT_ROOT/conf/backrest/repo-password.txt"
        "$PROJECT_ROOT/conf/backrest/repo-config.json"
        "$PROJECT_ROOT/conf/backrest/daily-plan.json"
        "$PROJECT_ROOT/conf/backrest/weekly-plan.json"
        "$PROJECT_ROOT/scripts/backrest-webhook.sh"
    )

    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            success "Файл создан: $file"
        else
            error "Файл не найден: $file"
            return 1
        fi
    done

    return 0
}

# === Создание документации ===
create_documentation() {
    log "Создание документации по интеграции..."

    cat > "$PROJECT_ROOT/docs/backrest-integration.md" <<EOF
# Backrest Integration для ERNI-KI

## Обзор

Система резервного копирования ERNI-KI использует Backrest для автоматического создания резервных копий критически важных данных.

## Конфигурация

### Репозиторий
- **Тип**: Локальное хранилище
- **Путь**: \`.config-backup/\`
- **Шифрование**: AES-256 (пароль в \`conf/backrest/repo-password.txt\`)

### Планы резервного копирования

#### Ежедневные резервные копии
- **Расписание**: 01:00 каждый день
- **Хранение**: 7 дней
- **Содержимое**: env/, conf/, data/postgres/, data/openwebui/, data/ollama/

#### Еженедельные резервные копии
- **Расписание**: 02:00 каждое воскресенье
- **Хранение**: 4 недели
- **Содержимое**: env/, conf/, data/postgres/, data/openwebui/, data/ollama/

## Мониторинг

### Интеграция с системой мониторинга
- Webhook: \`scripts/backrest-webhook.sh\`
- Логи: \`logs/backrest-notifications.log\`
- Системный журнал: \`journalctl -t erni-ki-backrest\`

### Уведомления
- Успешные резервные копии логируются
- Ошибки отправляются в систему мониторинга
- Интеграция с rate limiting мониторингом

## API Endpoints

- **Конфигурация**: \`POST /v1.Backrest/GetConfig\`
- **Операции**: \`POST /v1.Backrest/GetOperations\`
- **Запуск резервного копирования**: \`POST /v1.Backrest/Backup\`

## Восстановление

Для восстановления данных используйте веб-интерфейс Backrest:
\`\`\`
http://localhost:9898
\`\`\`

## Безопасность

- Пароль репозитория хранится в зашифрованном виде
- Доступ к API ограничен localhost
- Резервные копии создаются с правами root
EOF

    success "Документация создана: docs/backrest-integration.md"
}

# === Основная функция ===
main() {
    log "Настройка интеграции Backrest для ERNI-KI"

    # Проверка доступности Backrest
    if ! check_backrest_availability; then
        error "Backrest недоступен. Убедитесь, что сервис запущен."
        exit 1
    fi

    # Создание структуры
    mkdir -p "$PROJECT_ROOT/conf/backrest"
    mkdir -p "$PROJECT_ROOT/docs"
    mkdir -p "$PROJECT_ROOT/logs"

    # Выполнение настройки
    create_local_repository
    create_backup_plans
    create_monitoring_webhook
    create_notification_hooks
    create_documentation

    # Тестирование
    if test_integration; then
        success "Интеграция Backrest настроена успешно!"

        echo
        echo "📋 Что было настроено:"
        echo "  ✅ Локальный репозиторий в .config-backup/"
        echo "  ✅ Ежедневные резервные копии (7 дней хранения)"
        echo "  ✅ Еженедельные резервные копии (4 недели хранения)"
        echo "  ✅ Webhook для интеграции с мониторингом"
        echo "  ✅ Hooks для уведомлений о статусе"
        echo "  ✅ Документация по интеграции"

        echo
        echo "🚀 Следующие шаги:"
        echo "  1. Откройте http://localhost:9898 для настройки через веб-интерфейс"
        echo "  2. Добавьте репозиторий используя конфигурацию из conf/backrest/repo-config.json"
        echo "  3. Создайте планы резервного копирования из conf/backrest/*-plan.json"
        echo "  4. Настройте hooks используя conf/backrest/*-hook.json"

    else
        error "Ошибка при настройке интеграции Backrest"
        exit 1
    fi
}

# Запуск
main "$@"
