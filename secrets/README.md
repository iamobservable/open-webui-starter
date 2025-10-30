# 🔐 Docker Secrets для ERNI-KI

Эта директория содержит чувствительные данные (пароли, API ключи) для Docker Compose secrets.

## 📋 Структура

```
secrets/
├── postgres_password.txt           # Пароль PostgreSQL
├── litellm_db_password.txt        # Пароль БД для LiteLLM
├── litellm_api_key.txt            # API ключ LiteLLM
├── context7_api_key.txt           # API ключ Context7
├── vllm_api_key.txt               # API ключ VLLM
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
cp secrets/context7_api_key.txt.example secrets/context7_api_key.txt
cp secrets/vllm_api_key.txt.example secrets/vllm_api_key.txt

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

# Context7 API key
echo "ctx7sk-your-key" > secrets/context7_api_key.txt

# VLLM API key
echo "your-vllm-key" > secrets/vllm_api_key.txt

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

