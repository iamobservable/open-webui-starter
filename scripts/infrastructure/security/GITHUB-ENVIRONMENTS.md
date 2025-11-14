# 🔐 GitHub Environments Security Scripts

Набор скриптов для настройки и управления GitHub Environments в проекте ERNI-KI.

## 🚀 Быстрый старт

### 1. Полная автоматическая настройка

```bash
# Выполнить все шаги настройки автоматически
./setup-github-environments.sh && \
./configure-environment-protection.sh && \
./setup-environment-secrets.sh && \
./validate-environment-secrets.sh
```

### 2. Пошаговая настройка

```bash
# Шаг 1: Создание окружений
./setup-github-environments.sh

# Шаг 2: Настройка protection rules
./configure-environment-protection.sh

# Шаг 3: Добавление секретов
./setup-environment-secrets.sh

# Шаг 4: Валидация
./validate-environment-secrets.sh
```

## 📁 Описание скриптов

### `setup-github-environments.sh`

Создает три окружения (development, staging, production) с базовыми настройками.

**Использование:**

```bash
./setup-github-environments.sh
```

**Что делает:**

- Создает окружения development, staging, production
- Проверяет права доступа
- Логирует все операции

### `configure-environment-protection.sh`

Настраивает protection rules для каждого окружения:

- Development: без ограничений
- Staging: 1 reviewer, задержка 5 мин
- Production: 2 reviewers, задержка 10 мин, только protected branches

**Использование:**

```bash
./configure-environment-protection.sh
```

### `setup-environment-secrets.sh`

Добавляет environment-specific секреты:

- TUNNEL_TOKEN_DEV/STAGING/PROD
- OPENAI_API_KEY_DEV/STAGING/PROD
- CONTEXT7_API_KEY_DEV/STAGING/PROD
- ANTHROPIC_API_KEY_DEV/STAGING/PROD
- GOOGLE_API_KEY_DEV/STAGING/PROD

**Использование:**

```bash
./setup-environment-secrets.sh
```

⚠️ **ВАЖНО:** Production секреты создаются с placeholder значениями и должны
быть заменены на реальные!

### `validate-environment-secrets.sh`

Проверяет доступность и корректность всех секретов во всех окружениях.

**Использование:**

```bash
# Полная валидация
./validate-environment-secrets.sh

# Dry-run режим
./validate-environment-secrets.sh --dry-run

# Справка
./validate-environment-secrets.sh --help
```

## 🔧 Требования

### Предварительные требования

1. **GitHub CLI** установлен и настроен:

```bash
# Установка (Ubuntu/Debian)
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update && sudo apt install gh

# Аутентификация
gh auth login --scopes repo,admin:org
```

2. **jq** для обработки JSON:

```bash
sudo apt install jq
```

3. **openssl** для генерации секретов:

```bash
sudo apt install openssl
```

### Права доступа

Для выполнения скриптов требуются следующие права в GitHub:

- **repo** - полный доступ к репозиторию
- **admin:org** - управление организацией (для создания environments)

## 📊 Структура секретов

### Repository Level (9 секретов)

```
POSTGRES_PASSWORD      # Пароль PostgreSQL
JWT_SECRET            # JWT секретный ключ
WEBUI_SECRET_KEY      # Ключ OpenWebUI
LITELLM_MASTER_KEY    # Мастер-ключ LiteLLM
LITELLM_SALT_KEY      # Соль для шифрования LiteLLM
RESTIC_PASSWORD       # Пароль шифрования бэкапов
SEARXNG_SECRET        # Секретный ключ SearXNG
REDIS_PASSWORD        # Пароль Redis
BACKREST_PASSWORD     # Пароль Backrest
```

### Environment Level (5 секретов × 3 окружения = 15 секретов)

```
TUNNEL_TOKEN_DEV/STAGING/PROD          # Cloudflare tunnel токены
OPENAI_API_KEY_DEV/STAGING/PROD        # OpenAI API ключи
CONTEXT7_API_KEY_DEV/STAGING/PROD      # Context7 API ключи
ANTHROPIC_API_KEY_DEV/STAGING/PROD     # Anthropic API ключи
GOOGLE_API_KEY_DEV/STAGING/PROD        # Google API ключи
```

**Всего: 24 секрета**

## 🔍 Проверка и мониторинг

### Просмотр окружений

```bash
gh api repos/:owner/:repo/environments | jq '.[].name'
```

### Просмотр секретов

```bash
# Repository секреты
gh secret list

# Environment секреты
gh secret list --env development
gh secret list --env staging
gh secret list --env production
```

### Проверка protection rules

```bash
gh api repos/:owner/:repo/environments/production | jq '.protection_rules'
```

## 🚨 Troubleshooting

### Ошибка: "Environment not found"

```bash
# Проверить существование
gh api repos/:owner/:repo/environments | jq '.[].name'

# Создать заново
./setup-github-environments.sh
```

### Ошибка: "Insufficient permissions"

```bash
# Проверить права
gh auth status

# Переаутентификация
gh auth login --scopes repo,admin:org
```

### Ошибка: "Secret not found"

```bash
# Проверить секреты
gh secret list --env production

# Добавить секрет
gh secret set SECRET_NAME --env production --body "value"
```

## 📋 Чеклист после настройки

- [ ] Все 3 окружения созданы
- [ ] Protection rules настроены
- [ ] Все 24 секрета добавлены
- [ ] Production секреты заменены на реальные
- [ ] Валидация прошла успешно
- [ ] GitHub Actions workflows обновлены

## 🔄 Регулярное обслуживание

### Еженедельно

```bash
# Валидация секретов
./validate-environment-secrets.sh
```

### Ежемесячно

```bash
# Проверка использования API ключей
# Аудит изменений секретов
# Обновление документации
```

### Каждые 90 дней

```bash
# Ротация критических секретов
./rotate-secrets.sh --service all
```

## 🎯 Best Practices

1. **Никогда не коммитьте секреты в код**
2. **Используйте разные API ключи для разных окружений**
3. **Регулярно ротируйте секреты (каждые 90 дней)**
4. **Мониторьте использование API ключей**
5. **Заменяйте placeholder значения перед production**

## 📞 Поддержка

Для вопросов и проблем:

1. Проверьте [полную документацию](../../../docs/reference/github-environments-setup.md)
2. Создайте issue в репозитории
3. Обратитесь к Tech Lead команды

---

**Автор:** Альтэон Шульц (Tech Lead)  
**Последнее обновление:** 2025-09-19
