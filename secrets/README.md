# 🔐 Docker Secrets для ERNI-KI

Эта директория содержит чувствительные данные (пароли, API ключи) для Docker
Compose secrets.

## 📋 Структура

```
secrets/
├── postgres_password.txt           # Пароль PostgreSQL
├── litellm_db_password.txt        # Пароль БД для LiteLLM
├── litellm_api_key.txt            # API ключ LiteLLM
├── publicai_api_key.txt           # PublicAI ключ для внешних моделей LiteLLM
├── context7_api_key.txt           # API ключ Context7
├── vllm_api_key.txt               # API ключ VLLM
├── watchtower_api_token.txt       # Токен доступа к HTTP API Watchtower
├── grafana_admin_password.txt     # Пароль администратора Grafana
├── postgres_exporter_dsn.txt      # DSN для postgres-exporter
├── redis_exporter_url.txt         # JSON-карта host→пароль для redis-exporter
├── openwebui_secret_key.txt       # FastAPI SECRET_KEY для OpenWebUI
├── litellm_master_key.txt         # MASTER KEY LiteLLM
├── litellm_salt_key.txt           # SALT KEY LiteLLM
├── litellm_ui_password.txt        # Пароль UI LiteLLM
├── *.example                      # Примеры файлов
└── README.md                      # Этот файл
```

## 🚀 Быстрый старт

### 1. Создание секретов из примеров

```bash
# Скопировать примеры
cp secrets/postgres_password.txt.example secrets/postgres_password.txt
cp secrets/litellm_db_password.txt.example secrets/litellm_db_password.txt
cp secrets/litellm_api_key.txt.example secrets/litellm_api_key.txt
cp secrets/publicai_api_key.txt.example secrets/publicai_api_key.txt
cp secrets/context7_api_key.txt.example secrets/context7_api_key.txt
cp secrets/vllm_api_key.txt.example secrets/vllm_api_key.txt
cp secrets/watchtower_api_token.txt.example secrets/watchtower_api_token.txt
cp secrets/grafana_admin_password.txt.example secrets/grafana_admin_password.txt
cp secrets/postgres_exporter_dsn.txt.example secrets/postgres_exporter_dsn.txt
cp secrets/redis_exporter_url.txt.example secrets/redis_exporter_url.txt
cp secrets/openwebui_secret_key.txt.example secrets/openwebui_secret_key.txt
cp secrets/litellm_master_key.txt.example secrets/litellm_master_key.txt
cp secrets/litellm_salt_key.txt.example secrets/litellm_salt_key.txt
cp secrets/litellm_ui_password.txt.example secrets/litellm_ui_password.txt

# Установить права доступа
chmod 600 secrets/*.txt
```

### 2. Заполнение секретов

Отредактируйте каждый файл и замените placeholder значения на реальные:

```bash
# PostgreSQL password
echo "your-strong-password-here" > secrets/postgres_password.txt

# LiteLLM DB password
echo "your-litellm-db-password" > secrets/litellm_db_password.txt

# LiteLLM API key
echo "sk-your-api-key" > secrets/litellm_api_key.txt

# PublicAI API key (используется кастомным провайдером LiteLLM)
echo "zpka_your_publicai_key" > secrets/publicai_api_key.txt

# Context7 API key
echo "ctx7sk-your-key" > secrets/context7_api_key.txt

# VLLM API key
echo "your-vllm-key" > secrets/vllm_api_key.txt

# Watchtower HTTP API token
echo "long-random-token" > secrets/watchtower_api_token.txt

# Grafana admin password
echo "your-very-strong-password" > secrets/grafana_admin_password.txt

# Postgres exporter DSN
echo "postgresql://postgres:your-password@db:5432/openwebui?sslmode=disable" > secrets/postgres_exporter_dsn.txt

# Redis exporter password map (JSON)
echo '{"redis://redis:6379":"your-redis-password"}' > secrets/redis_exporter_url.txt
# Если аутентификация отключена, оставьте значение пустым: {"redis://redis:6379":""}

# OpenWebUI secret key (64 hex chars)
openssl rand -hex 32 > secrets/openwebui_secret_key.txt

# LiteLLM master/salt keys и пароль UI
openssl rand -base64 48 | tr -d '=+/ ' | cut -c1-48 > secrets/litellm_master_key.txt
openssl rand -hex 32 > secrets/litellm_salt_key.txt
openssl rand -base64 48 | tr -d '=+/ ' | cut -c1-32 > secrets/litellm_ui_password.txt

# Установить права доступа
chmod 600 secrets/*.txt
```

## 🔒 Безопасность

### Важно!

- ✅ Файлы `*.txt` **НЕ** должны быть в git (добавлены в `.gitignore`)
- ✅ Права доступа должны быть `600` (только владелец может читать/писать)
- ✅ Файлы `*.example` **ДОЛЖНЫ** быть в git (для документации)
- ⚠️ **НИКОГДА** не коммитьте реальные секреты в git!

### Проверка безопасности

```bash
# Проверить права доступа
ls -l secrets/*.txt

# Должно быть: -rw------- (600)
# Если нет, исправить:
chmod 600 secrets/*.txt

# Проверить что секреты не в git
git status secrets/

# Должно показать только *.example файлы
```

## 📖 Использование в Docker Compose

Секреты автоматически монтируются в контейнеры через `compose.yml`:

```yaml
secrets:
  postgres_password:
    file: ./secrets/postgres_password.txt
  litellm_api_key:
    file: ./secrets/litellm_api_key.txt

services:
  db:
    secrets:
      - postgres_password
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/postgres_password
```

Внутри контейнера секреты доступны в `/run/secrets/`:

```bash
# Пример чтения секрета в контейнере
cat /run/secrets/postgres_password
```

## 🔄 Ротация секретов

При смене паролей/ключей:

1. Обновите файлы в `secrets/`
2. Перезапустите сервисы:

```bash
docker compose down
docker compose up -d
```

## 📝 Генерация безопасных паролей

```bash
# Генерация случайного пароля (32 символа)
openssl rand -base64 32

# Генерация пароля с специальными символами
openssl rand -base64 32 | tr -d "=+/" | cut -c1-32

# Генерация UUID (для API ключей)
uuidgen
```

## ⚠️ Troubleshooting

### Проблема: Сервис не может прочитать секрет

```bash
# Проверить права доступа
ls -l secrets/*.txt

# Проверить содержимое (без вывода в консоль!)
wc -l secrets/*.txt

# Проверить что файл не пустой
[ -s secrets/postgres_password.txt ] && echo "OK" || echo "EMPTY"
```

### Проблема: Docker Compose не видит секреты

```bash
# Проверить конфигурацию
docker compose config | grep -A 5 secrets

# Проверить что файлы существуют
ls -l secrets/*.txt
```

## 📚 Дополнительная информация

- [Docker Secrets Documentation](https://docs.docker.com/engine/swarm/secrets/)
- [Best Practices for Secrets Management](https://docs.docker.com/compose/use-secrets/)
- [ERNI-KI Security Guide](../docs/security-guide.md)

---

**Создано:** 2025-10-30  
**Обновлено:** 2025-10-30  
**Версия:** 1.0
