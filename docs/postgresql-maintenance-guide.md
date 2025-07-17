# 🔧 Руководство по эксплуатации оптимизированной PostgreSQL архитектуры

**Версия:** 1.1
**Дата:** 15 июля 2025
**Для:** ERNI-KI система

## 🎯 Краткий обзор

После оптимизации PostgreSQL архитектуры система использует:
- **Отдельные пользователи БД:** openwebui_user и litellm_user
- **Совместное использование:** 54 таблицы в одной БД
- **Connection pooling:** Настроен для обоих сервисов
- **Persistent storage:** LiteLLM сохраняет данные в PostgreSQL

## 🔍 Ежедневный мониторинг

### Быстрая проверка здоровья системы

```bash
# Статус всех сервисов
docker-compose ps

# Диагностика PostgreSQL
./scripts/diagnose-postgresql-shared-usage.sh

# Проверка API
curl -s http://localhost:8080/health  # OpenWebUI
curl -s http://localhost:4000/health/liveliness  # LiteLLM
```

### Ключевые метрики для мониторинга

**PostgreSQL подключения:**
```bash
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "
SELECT usename, COUNT(*) as connections
FROM pg_stat_activity
WHERE datname = 'openwebui'
GROUP BY usename;
"
```

**Размеры таблиц:**
```bash
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "
SELECT
    CASE WHEN tablename LIKE 'LiteLLM_%' THEN 'LiteLLM' ELSE 'OpenWebUI' END as service,
    COUNT(*) as tables,
    pg_size_pretty(SUM(pg_total_relation_size(schemaname||'.'||tablename))) as size
FROM pg_tables
WHERE schemaname = 'public'
GROUP BY CASE WHEN tablename LIKE 'LiteLLM_%' THEN 'LiteLLM' ELSE 'OpenWebUI' END;
"
```

## 🚨 Устранение неполадок

### Проблема: OpenWebUI не может подключиться к БД

**Симптомы:**
- OpenWebUI показывает ошибки подключения
- Health check возвращает ошибку

**Решение:**
```bash
# 1. Проверить пользователя БД
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "\du openwebui_user"

# 2. Проверить права доступа
docker exec erni-ki-db-1 psql -U openwebui_user -d openwebui -c "SELECT 1;"

# 3. Перезапустить OpenWebUI
docker-compose restart openwebui
```

### Проблема: LiteLLM теряет virtual keys

**Симптомы:**
- Virtual keys исчезают после перезапуска
- API возвращает ошибки аутентификации

**Решение:**
```bash
# 1. Проверить подключение к БД
docker exec erni-ki-db-1 psql -U litellm_user -d openwebui -c "
SELECT COUNT(*) FROM \"LiteLLM_VerificationToken\";
"

# 2. Проверить конфигурацию
grep -i database env/litellm.env
grep -i database_url conf/litellm/config-simple.yaml

# 3. Перезапустить с миграциями
docker-compose stop litellm
docker-compose up -d litellm
```

### Проблема: Высокое количество подключений

**Симптомы:**
- PostgreSQL логи показывают "too many connections"
- Медленная работа API

**Решение:**
```bash
# 1. Проверить активные подключения
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "
SELECT COUNT(*) as total_connections FROM pg_stat_activity;
"

# 2. Настроить connection pooling
# Обновить DATABASE_POOL_SIZE в env/openwebui.env
# Обновить DATABASE_CONNECTION_POOL_LIMIT в env/litellm.env

# 3. Перезапустить сервисы
docker-compose restart openwebui litellm
```

## 🔄 Регулярное обслуживание

### Еженедельные задачи

**1. Backup проверка:**
```bash
# Проверить статус Backrest
curl -s http://localhost:9898/api/v1/repos/local/snapshots | jq '.snapshots[-1]'

# Создать manual backup
curl -X POST http://localhost:9898/api/v1/repos/local/backup \
  -H "Content-Type: application/json" \
  -d '{"plan_id": "weekly-maintenance"}'
```

**2. Очистка логов:**
```bash
# Очистить старые логи Docker
docker system prune -f

# Архивировать логи PostgreSQL (если нужно)
docker exec erni-ki-db-1 find /var/log -name "*.log" -mtime +7 -delete
```

**3. Анализ производительности:**
```bash
# Запустить полную диагностику
./scripts/diagnose-postgresql-shared-usage.sh > weekly-report-$(date +%Y%m%d).txt

# Проверить медленные запросы (если pg_stat_statements включен)
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "
SELECT query, calls, total_time, mean_time
FROM pg_stat_statements
WHERE mean_time > 100
ORDER BY mean_time DESC
LIMIT 5;
"
```

### Ежемесячные задачи

**1. Обновление паролей (опционально):**
```bash
# Генерировать новые пароли
NEW_OW_PASS=$(openssl rand -base64 32)
NEW_LL_PASS=$(openssl rand -base64 32)

# Обновить в PostgreSQL
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "
ALTER USER openwebui_user PASSWORD '$NEW_OW_PASS';
ALTER USER litellm_user PASSWORD '$NEW_LL_PASS';
"

# Обновить в конфигурациях
# env/openwebui.env, env/litellm.env, conf/litellm/config-simple.yaml
```

**2. Анализ роста данных:**
```bash
# Размеры таблиц по месяцам
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "
SELECT
    schemaname||'.'||tablename as table_name,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size,
    pg_total_relation_size(schemaname||'.'||tablename) as size_bytes
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY size_bytes DESC
LIMIT 10;
"
```

## 📊 Мониторинг алерты

### Критические пороги

**Подключения к БД:**
- **Предупреждение:** >50 активных подключений
- **Критично:** >80 активных подключений

**Размер БД:**
- **Предупреждение:** >5GB общий размер
- **Критично:** >10GB общий размер

**Response time:**
- **Предупреждение:** >2 секунды для API
- **Критично:** >5 секунд для API

### Скрипт автоматического мониторинга

```bash
#!/bin/bash
# Добавить в crontab: */15 * * * * /path/to/monitor.sh

CONNECTIONS=$(docker exec erni-ki-db-1 psql -U postgres -d openwebui -t -c "SELECT COUNT(*) FROM pg_stat_activity;" | tr -d ' ')

if [ "$CONNECTIONS" -gt 80 ]; then
    echo "CRITICAL: $CONNECTIONS active connections" | logger
elif [ "$CONNECTIONS" -gt 50 ]; then
    echo "WARNING: $CONNECTIONS active connections" | logger
fi

# Проверка API
if ! curl -s http://localhost:8080/health > /dev/null; then
    echo "CRITICAL: OpenWebUI API down" | logger
fi

if ! curl -s http://localhost:4000/health/liveliness > /dev/null; then
    echo "CRITICAL: LiteLLM API down" | logger
fi
```

## 🔧 Конфигурационные файлы

### Ключевые настройки для мониторинга

**env/openwebui.env:**
```env
DATABASE_POOL_SIZE=20          # Размер пула подключений
DATABASE_POOL_TIMEOUT=30       # Таймаут подключения
ENABLE_METRICS=true            # Включить метрики
```

**env/litellm.env:**
```env
DATABASE_CONNECTION_POOL_LIMIT=10    # Лимит подключений
DATABASE_CONNECTION_TIMEOUT=60       # Таймаут подключения
ENABLE_HEALTH_CHECKS=True           # Health checks
```

### Backup конфигурация

**Backrest планы:**
- **Ежедневно:** 7 дней хранения
- **Еженедельно:** 4 недели хранения
- **Ежемесячно:** 12 месяцев хранения

## 📞 Контакты экстренной поддержки

**Ответственный:** Альтэон Шульц (Tech Lead)
**Документация:** docs/postgresql-optimization-guide.md
**Диагностика:** scripts/diagnose-postgresql-shared-usage.sh
**Отчеты:** docs/postgresql-optimization-completion-report.md

## 🚀 Планы развития

### Краткосрочные улучшения
1. **PgBouncer интеграция** - Внешний connection pooler
2. **SSL/TLS шифрование** - Защищенные соединения
3. **Prometheus метрики** - Расширенный мониторинг

### Долгосрочные улучшения
1. **Разделение схем** - Изоляция данных сервисов
2. **Read replicas** - Масштабирование чтения
3. **Автоматические алерты** - Интеграция с системами уведомлений

---

**Версия руководства:** 1.0
**Последнее обновление:** 15.07.2025
**Статус:** Готово к использованию
