# OneDrive Integration Troubleshooting Guide

**Дата:** 29 августа 2025  
**Версия:** 1.0  
**Автор:** Альтэон Шульц, Tech Lead

## 📋 Обзор

Данное руководство содержит решения типичных проблем при интеграции OneDrive в ERNI-KI системе,
диагностические процедуры и рекомендации по устранению неполадок.

---

## 🔍 Диагностические команды

### Быстрая диагностика

```bash
# Проверка статуса OneDrive интеграции
./scripts/test-onedrive-integration.sh

# Проверка переменных окружения
docker-compose exec openwebui env | grep -E "ONEDRIVE|AZURE|MICROSOFT_GRAPH"

# Проверка логов OpenWebUI
docker-compose logs openwebui | grep -i onedrive

# Проверка состояния базы данных
docker-compose exec db psql -U postgres -d openwebui -c "SELECT COUNT(*) FROM onedrive_files;"
```

### Детальная диагностика

```bash
# Проверка Azure App Registration
az ad app show --id $AZURE_CLIENT_ID

# Проверка разрешений приложения
az ad app permission list --id $AZURE_CLIENT_ID

# Тест Microsoft Graph API
curl -H "Authorization: Bearer $ACCESS_TOKEN" https://graph.microsoft.com/v1.0/me/drive

# Проверка OAuth endpoints
curl -I https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/authorize
```

---

## ❌ Частые проблемы и решения

### 1. Ошибки аутентификации

#### Проблема: "invalid_client" ошибка

**Симптомы:**

- HTTP 400 Bad Request при OAuth запросах
- Сообщение: "AADSTS70002: Error validating credentials"

**Причины:**

- Неверный AZURE_CLIENT_ID
- Неверный AZURE_CLIENT_SECRET
- Приложение не найдено в tenant

**Решение:**

```bash
# 1. Проверить client_id
az ad app show --id $AZURE_CLIENT_ID

# 2. Проверить client_secret (создать новый если нужно)
az ad app credential reset --id $AZURE_CLIENT_ID --append

# 3. Обновить переменные окружения
echo "AZURE_CLIENT_ID=new-client-id" >> env/openwebui.env
echo "AZURE_CLIENT_SECRET=new-client-secret" >> env/openwebui.env

# 4. Перезапустить OpenWebUI
docker-compose restart openwebui
```

#### Проблема: "insufficient_privileges" ошибка

**Симптомы:**

- HTTP 403 Forbidden при доступе к OneDrive
- Сообщение: "Insufficient privileges to complete the operation"

**Причины:**

- Отсутствует admin consent для разрешений
- Неправильные разрешения в App Registration

**Решение:**

```bash
# 1. Предоставить admin consent
az ad app permission admin-consent --id $AZURE_CLIENT_ID

# 2. Проверить статус разрешений
az ad app permission list --id $AZURE_CLIENT_ID

# 3. Добавить недостающие разрешения
az ad app permission add --id $AZURE_CLIENT_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions df021288-bdef-4463-88db-98f22de89214=Role
```

#### Проблема: "invalid_grant" ошибка

**Симптомы:**

- Ошибка при обмене authorization code на access token
- Сообщение: "AADSTS70008: The provided authorization code or refresh token has expired"

**Причины:**

- Authorization code истек (действует 10 минут)
- Неверный redirect_uri
- Проблемы с системным временем

**Решение:**

```bash
# 1. Проверить redirect_uri в App Registration
az ad app show --id $AZURE_CLIENT_ID --query "web.redirectUris"

# 2. Обновить redirect_uri если нужно
az ad app update --id $AZURE_CLIENT_ID \
  --web-redirect-uris "https://your-domain.com/api/auth/microsoft/callback"

# 3. Проверить системное время
timedatectl status

# 4. Получить новый authorization code
# (повторить OAuth flow)
```

### 2. Проблемы с API запросами

#### Проблема: Rate limiting (429 ошибки)

**Симптомы:**

- HTTP 429 Too Many Requests
- Заголовок "Retry-After" в ответе

**Причины:**

- Превышение лимитов Microsoft Graph API
- Слишком частые запросы к OneDrive

**Решение:**

```bash
# 1. Настроить exponential backoff
cat >> env/openwebui.env << 'EOF'
ONEDRIVE_RETRY_ATTEMPTS=5
ONEDRIVE_RETRY_DELAY=1
ONEDRIVE_BACKOFF_MULTIPLIER=2
ONEDRIVE_MAX_RETRY_DELAY=60
EOF

# 2. Уменьшить частоту синхронизации
echo "ONEDRIVE_SYNC_INTERVAL=60" >> env/openwebui.env

# 3. Уменьшить размер batch запросов
echo "ONEDRIVE_BATCH_SIZE=10" >> env/openwebui.env

# 4. Перезапустить OpenWebUI
docker-compose restart openwebui
```

#### Проблема: Token expiration

**Симптомы:**

- HTTP 401 Unauthorized после периода бездействия
- Сообщение: "Access token has expired"

**Причины:**

- Access token истек (обычно через 1 час)
- Refresh token не работает или истек

**Решение:**

```bash
# 1. Включить автоматический refresh токенов
cat >> env/openwebui.env << 'EOF'
ONEDRIVE_AUTO_TOKEN_REFRESH=true
ONEDRIVE_TOKEN_REFRESH_THRESHOLD=300
EOF

# 2. Проверить offline_access разрешение
az ad app permission list --id $AZURE_CLIENT_ID | grep offline_access

# 3. Добавить offline_access если отсутствует
az ad app permission add --id $AZURE_CLIENT_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 7427e0e9-2fba-42fe-b0c0-848c9e6a8182=Scope

# 4. Перезапустить OpenWebUI
docker-compose restart openwebui
```

### 3. Проблемы с синхронизацией файлов

#### Проблема: Файлы не синхронизируются

**Симптомы:**

- Новые файлы в OneDrive не появляются в RAG системе
- Статус синхронизации "pending" или "failed"

**Причины:**

- Проблемы с webhook подписками
- Ошибки обработки файлов
- Проблемы с базой данных

**Решение:**

```bash
# 1. Проверить статус синхронизации в БД
docker-compose exec db psql -U postgres -d openwebui -c "
SELECT sync_status, COUNT(*)
FROM onedrive_files
GROUP BY sync_status;
"

# 2. Проверить логи обработки файлов
docker-compose logs openwebui | grep -E "onedrive|sync|webhook"

# 3. Принудительная синхронизация
docker-compose exec openwebui python3 -c "
# Псевдокод для принудительной синхронизации
import os
if os.getenv('ENABLE_ONEDRIVE_INTEGRATION') == 'true':
    print('Запуск принудительной синхронизации...')
    # Здесь будет код синхронизации
"

# 4. Перезапустить webhook подписки
# (требует реализации в OpenWebUI)
```

#### Проблема: Большие файлы не обрабатываются

**Симптомы:**

- Файлы больше определенного размера пропускаются
- Ошибки timeout при загрузке

**Причины:**

- Превышение ONEDRIVE_MAX_FILE_SIZE
- Timeout при загрузке больших файлов
- Недостаток памяти для обработки

**Решение:**

```bash
# 1. Увеличить лимит размера файла (200MB)
echo "ONEDRIVE_MAX_FILE_SIZE=209715200" >> env/openwebui.env

# 2. Увеличить timeout для загрузки
echo "ONEDRIVE_DOWNLOAD_TIMEOUT=300" >> env/openwebui.env

# 3. Включить chunked download для больших файлов
echo "ONEDRIVE_ENABLE_CHUNKED_DOWNLOAD=true" >> env/openwebui.env
echo "ONEDRIVE_CHUNK_SIZE=10485760" >> env/openwebui.env

# 4. Перезапустить OpenWebUI
docker-compose restart openwebui
```

### 4. Проблемы с базой данных

#### Проблема: Таблицы OneDrive не существуют

**Симптомы:**

- Ошибки "relation does not exist" в логах
- Невозможность сохранить метаданные файлов

**Причины:**

- Схема базы данных не применена
- Миграции не выполнены

**Решение:**

```bash
# 1. Применить схему базы данных
docker-compose exec db psql -U postgres -d openwebui -f /path/to/onedrive-schema.sql

# Или если файл схемы на хосте:
psql $DATABASE_URL -f onedrive-schema.sql

# 2. Проверить создание таблиц
docker-compose exec db psql -U postgres -d openwebui -c "
SELECT table_name FROM information_schema.tables
WHERE table_name LIKE 'onedrive_%';
"

# 3. Проверить права доступа
docker-compose exec db psql -U postgres -d openwebui -c "
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO postgres;
"
```

#### Проблема: Ошибки векторного поиска

**Симптомы:**

- Ошибки при создании embeddings
- Медленный поиск по OneDrive файлам

**Причины:**

- Отсутствует расширение pgvector
- Неправильные индексы

**Решение:**

```bash
# 1. Проверить расширение pgvector
docker-compose exec db psql -U postgres -d openwebui -c "
SELECT * FROM pg_extension WHERE extname = 'vector';
"

# 2. Создать расширение если отсутствует
docker-compose exec db psql -U postgres -d openwebui -c "
CREATE EXTENSION IF NOT EXISTS vector;
"

# 3. Пересоздать индексы для векторного поиска
docker-compose exec db psql -U postgres -d openwebui -c "
DROP INDEX IF EXISTS idx_onedrive_embeddings_vector;
CREATE INDEX idx_onedrive_embeddings_vector
ON onedrive_embeddings USING ivfflat (embedding vector_cosine_ops);
"
```

---

## 🔧 Инструменты диагностики

### Скрипт проверки конфигурации

```bash
#!/bin/bash
# onedrive-config-check.sh

echo "=== OneDrive Configuration Check ==="

# Проверка переменных окружения
required_vars=(
    "ENABLE_ONEDRIVE_INTEGRATION"
    "AZURE_CLIENT_ID"
    "AZURE_CLIENT_SECRET"
    "AZURE_TENANT_ID"
    "MICROSOFT_GRAPH_ENDPOINT"
)

for var in "${required_vars[@]}"; do
    value=$(docker-compose exec -T openwebui env | grep "^$var=" | cut -d'=' -f2)
    if [[ -n "$value" ]]; then
        echo "✅ $var: ${value:0:20}..."
    else
        echo "❌ $var: NOT SET"
    fi
done

# Проверка доступности сервисов
echo -e "\n=== Service Availability ==="
services=("https://graph.microsoft.com/v1.0" "$OPENWEBUI_URL/health")

for service in "${services[@]}"; do
    if curl -s --max-time 5 "$service" >/dev/null; then
        echo "✅ $service: Available"
    else
        echo "❌ $service: Unavailable"
    fi
done
```

### Скрипт очистки токенов

```bash
#!/bin/bash
# onedrive-token-cleanup.sh

echo "=== OneDrive Token Cleanup ==="

# Очистка истекших токенов из базы данных
docker-compose exec db psql -U postgres -d openwebui -c "
DELETE FROM onedrive_tokens
WHERE expires_at < NOW() - INTERVAL '1 day';
"

# Очистка кэша Redis (если используется)
if docker-compose ps redis | grep -q "Up"; then
    docker-compose exec redis redis-cli FLUSHDB
    echo "✅ Redis cache cleared"
fi

echo "✅ Token cleanup completed"
```

---

## 📊 Мониторинг и алертинг

### Ключевые метрики для мониторинга

```yaml
# Prometheus метрики
onedrive_auth_failures_total onedrive_api_requests_total{status="4xx|5xx"}
onedrive_token_refresh_failures_total onedrive_sync_lag_seconds
onedrive_file_processing_errors_total
```

### Grafana алерты

```yaml
# Критические алерты
- alert: OneDriveAuthFailure
  expr: increase(onedrive_auth_failures_total[5m]) > 5
  for: 1m
  labels:
    severity: critical
  annotations:
    summary: 'Multiple OneDrive authentication failures'

- alert: OneDriveAPIErrors
  expr: rate(onedrive_api_requests_total{status=~"4xx|5xx"}[5m]) > 0.1
  for: 2m
  labels:
    severity: warning
  annotations:
    summary: 'High OneDrive API error rate'
```

---

## 📚 Дополнительные ресурсы

### Полезные ссылки

- [Microsoft Graph API Documentation](https://docs.microsoft.com/en-us/graph/)
- [Azure App Registration Guide](https://docs.microsoft.com/en-us/azure/active-directory/develop/quickstart-register-app)
- [OAuth 2.0 Troubleshooting](https://docs.microsoft.com/en-us/azure/active-directory/develop/reference-aadsts-error-codes)

### Команды для экстренного восстановления

```bash
# Полный перезапуск OneDrive интеграции
docker-compose restart openwebui

# Очистка всех OneDrive данных (ОСТОРОЖНО!)
docker-compose exec db psql -U postgres -d openwebui -c "
TRUNCATE TABLE onedrive_embeddings, onedrive_files, onedrive_tokens CASCADE;
"

# Восстановление из backup
# docker-compose exec db psql -U postgres -d openwebui < onedrive-backup.sql
```

### Контакты поддержки

- **Tech Lead:** Альтэон Шульц
- **Документация:** `docs/onedrive-integration-guide.md`
- **Скрипты:** `scripts/setup-onedrive-integration.sh`, `scripts/test-onedrive-integration.sh`
