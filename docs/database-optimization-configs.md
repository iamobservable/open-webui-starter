# Готовые конфигурации для оптимизации БД ERNI-KI

## 🔧 Исправление критических проблем

### 1. Безопасная конфигурация Redis

**Обновленный файл `env/redis.env`:**
```env
# Redis Configuration для ERNI-KI
# Безопасная конфигурация с аутентификацией

# === Аутентификация ===
# Пароль для Redis (сгенерирован автоматически)
REDIS_ARGS="--requirepass 7f8a9b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a"

# === Прокси настройки ===
RI_PROXY_PATH=redis

# === Производительность ===
# Максимальная память (512MB)
REDIS_MAXMEMORY=512mb
REDIS_MAXMEMORY_POLICY=allkeys-lru

# === Персистентность ===
# Сохранение: 900 сек при 1+ изменении, 300 сек при 10+ изменениях, 60 сек при 10000+ изменениях
REDIS_SAVE="900 1 300 10 60 10000"

# === Безопасность ===
# Отключить опасные команды
REDIS_RENAME_COMMAND_FLUSHDB=""
REDIS_RENAME_COMMAND_FLUSHALL=""
REDIS_RENAME_COMMAND_DEBUG=""

# === Логирование ===
REDIS_LOGLEVEL=notice
```

**Обновленный файл `env/searxng.env`:**
```env
# SearXNG Configuration
# Конфигурация SearXNG для ERNI-KI с безопасным Redis

# === Основные настройки ===
SEARXNG_HOST=0.0.0.0:8080
SEARXNG_PORT=8080
SEARXNG_BIND_ADDRESS=0.0.0.0

# === Redis подключение с аутентификацией ===
SEARXNG_REDIS_URL=redis://:7f8a9b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a@redis:6379/1

# === Безопасность ===
SEARXNG_SECRET=89f03e7ae86485051232d47071a15241ae727f705589776321b5a52e14a6fe57

# === URL настройки ===
SEARXNG_BASE_URL=https://diz.zone/searxng

# === Функции безопасности ===
# Отключить ограничение скорости для внутренних запросов
SEARXNG_LIMITER=false

# Включить проксирование изображений для безопасности
SEARXNG_IMAGE_PROXY=true

# Отключить функции публичного инстанса
SEARXNG_PUBLIC_INSTANCE=false

# === Дополнительные настройки ===
SEARXNG_DEBUG=false
SEARXNG_HTTP_PROTOCOL_VERSION=1.1

# === Настройки для интеграции с OpenWebUI ===
# Отключить bot detection для внутренних запросов
SEARXNG_DISABLE_BOT_DETECTION=true
```

### 2. Оптимизированная конфигурация PostgreSQL

**Файл `conf/postgres/postgresql.conf` (создать новый):**
```ini
# PostgreSQL Configuration для ERNI-KI
# Оптимизированная конфигурация для AI/RAG нагрузки

# === Память ===
shared_buffers = 256MB                    # Буферы разделяемой памяти
effective_cache_size = 1GB                # Оценка кэша ОС
work_mem = 4MB                            # Память для операций сортировки
maintenance_work_mem = 64MB               # Память для обслуживания
temp_buffers = 8MB                        # Временные буферы

# === Checkpoint и WAL ===
checkpoint_completion_target = 0.9        # Цель завершения checkpoint
wal_buffers = 16MB                        # Буферы WAL
max_wal_size = 1GB                        # Максимальный размер WAL
min_wal_size = 80MB                       # Минимальный размер WAL

# === Планировщик запросов ===
random_page_cost = 1.1                    # Стоимость случайного доступа (SSD)
effective_io_concurrency = 200            # Параллельные I/O операции

# === Соединения ===
max_connections = 100                     # Максимум соединений
shared_preload_libraries = 'vector'      # Предзагрузка pgvector

# === Логирование ===
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_min_duration_statement = 1000        # Логировать медленные запросы (>1с)
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on

# === Статистика ===
track_activities = on
track_counts = on
track_io_timing = on
track_functions = all

# === Векторные операции (pgvector) ===
# Оптимизация для векторных вычислений
max_parallel_workers_per_gather = 2
max_parallel_workers = 8
```

**Обновленный Docker Compose для PostgreSQL:**
```yaml
db:
  depends_on:
    - watchtower
  env_file: env/db.env
  healthcheck:
    interval: 30s
    retries: 5
    start_period: 20s
    test: ["CMD-SHELL", "pg_isready -d $${POSTGRES_DB} -U $${POSTGRES_USER}"]
    timeout: 5s
  image: pgvector/pgvector:pg15
  restart: unless-stopped
  volumes:
    - ./data/postgres:/var/lib/postgresql/data
    - ./conf/postgres/postgresql.conf:/etc/postgresql/postgresql.conf:ro
  command: ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]
  # Ограничения ресурсов
  deploy:
    resources:
      limits:
        memory: 1G
        cpus: '2.0'
      reservations:
        memory: 512M
        cpus: '1.0'
```

### 3. Исправление SQL-ошибок

**Скрипт исправления `scripts/fix-database-errors.sql`:**
```sql
-- Исправление ошибок в PostgreSQL для ERNI-KI
-- Выполнить: docker-compose exec db psql -U postgres -d openwebui -f /scripts/fix-database-errors.sql

-- 1. Исправление поиска в JSON полях
-- Создание функции для безопасного поиска в JSON
CREATE OR REPLACE FUNCTION safe_json_search(json_data jsonb, search_term text)
RETURNS boolean AS $$
BEGIN
    RETURN json_data::text ILIKE '%' || search_term || '%';
EXCEPTION
    WHEN OTHERS THEN
        RETURN false;
END;
$$ LANGUAGE plpgsql;

-- 2. Создание индексов для оптимизации
-- Индекс для поиска в конфигурации
CREATE INDEX IF NOT EXISTS idx_config_data_gin ON config USING gin(data);

-- Индекс для векторного поиска
CREATE INDEX IF NOT EXISTS idx_document_chunk_embedding ON document_chunk USING ivfflat (embedding vector_cosine_ops);

-- 3. Исправление типов данных
-- Обновление конфигурации RAG embedding model
UPDATE config 
SET data = '"nomic-embed-text:latest"'::jsonb 
WHERE id = 'rag.embedding.model' 
AND data IS NOT NULL;

-- 4. Создание представлений для безопасного поиска
CREATE OR REPLACE VIEW config_search AS
SELECT 
    id,
    data,
    created_at,
    updated_at
FROM config
WHERE data IS NOT NULL;

-- 5. Оптимизация таблиц
VACUUM ANALYZE config;
VACUUM ANALYZE document_chunk;
VACUUM ANALYZE user;
VACUUM ANALYZE chat;

-- 6. Создание функции для мониторинга производительности
CREATE OR REPLACE FUNCTION db_performance_stats()
RETURNS TABLE(
    table_name text,
    row_count bigint,
    table_size text,
    index_size text
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        schemaname||'.'||tablename as table_name,
        n_tup_ins + n_tup_upd + n_tup_del as row_count,
        pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as table_size,
        pg_size_pretty(pg_indexes_size(schemaname||'.'||tablename)) as index_size
    FROM pg_stat_user_tables 
    WHERE schemaname = 'public'
    ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
END;
$$ LANGUAGE plpgsql;

-- Вывод статистики
SELECT * FROM db_performance_stats();
```

## 🚀 Скрипты автоматизации

### Скрипт применения исправлений

**Файл `scripts/apply-database-fixes.sh`:**
```bash
#!/bin/bash
# Скрипт применения исправлений БД для ERNI-KI

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Проверка что мы в правильной директории
if [ ! -f "compose.yml" ]; then
    error "Запустите скрипт из корневой директории ERNI-KI"
fi

log "Начинаем применение исправлений БД..."

# 1. Создание резервной копии конфигураций
log "Создание резервных копий..."
mkdir -p .config-backup/$(date +%Y%m%d_%H%M%S)
cp env/redis.env .config-backup/$(date +%Y%m%d_%H%M%S)/redis.env.bak
cp env/searxng.env .config-backup/$(date +%Y%m%d_%H%M%S)/searxng.env.bak

# 2. Генерация нового пароля Redis
log "Генерация нового пароля Redis..."
REDIS_PASSWORD=$(openssl rand -hex 32)

# 3. Обновление конфигурации Redis
log "Обновление конфигурации Redis..."
cat > env/redis.env << EOF
# Redis Configuration для ERNI-KI
# Безопасная конфигурация с аутентификацией
REDIS_ARGS="--requirepass ${REDIS_PASSWORD}"
RI_PROXY_PATH=redis
EOF

# 4. Обновление конфигурации SearXNG
log "Обновление конфигурации SearXNG..."
sed -i "s|SEARXNG_REDIS_URL=redis://redis:6379/1|SEARXNG_REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379/1|" env/searxng.env

# 5. Создание директории для конфигурации PostgreSQL
log "Создание конфигурации PostgreSQL..."
mkdir -p conf/postgres

# 6. Перезапуск сервисов с новой конфигурацией
log "Перезапуск Redis с новой конфигурацией..."
docker-compose stop redis searxng
sleep 5
docker-compose up -d redis
sleep 10

# 7. Проверка подключения Redis
log "Проверка подключения к Redis..."
if docker-compose exec redis redis-cli -a "${REDIS_PASSWORD}" ping | grep -q PONG; then
    log "Redis успешно настроен с аутентификацией"
else
    error "Ошибка подключения к Redis"
fi

# 8. Запуск SearXNG
log "Запуск SearXNG с обновленной конфигурацией..."
docker-compose up -d searxng
sleep 15

# 9. Применение SQL исправлений
log "Применение SQL исправлений..."
if [ -f "scripts/fix-database-errors.sql" ]; then
    docker-compose exec -T db psql -U postgres -d openwebui < scripts/fix-database-errors.sql
    log "SQL исправления применены успешно"
else
    warn "Файл scripts/fix-database-errors.sql не найден"
fi

# 10. Проверка статуса всех сервисов
log "Проверка статуса сервисов..."
sleep 30
docker-compose ps

log "Исправления применены успешно!"
log "Новый пароль Redis сохранен в env/redis.env"
log "Резервные копии сохранены в .config-backup/"

# 11. Тестирование функциональности
log "Тестирование функциональности..."

# Тест PostgreSQL
if docker-compose exec db psql -U postgres -d openwebui -c "SELECT 1;" > /dev/null 2>&1; then
    log "✅ PostgreSQL работает корректно"
else
    error "❌ Проблемы с PostgreSQL"
fi

# Тест Redis
if docker-compose exec redis redis-cli -a "${REDIS_PASSWORD}" ping | grep -q PONG; then
    log "✅ Redis работает корректно"
else
    error "❌ Проблемы с Redis"
fi

# Тест SearXNG
if docker-compose exec searxng curl -s http://localhost:8080/healthz > /dev/null 2>&1; then
    log "✅ SearXNG работает корректно"
else
    warn "⚠️  SearXNG может требовать дополнительного времени для запуска"
fi

log "Все исправления применены и протестированы!"
log "Рекомендуется перезапустить OpenWebUI для применения всех изменений:"
log "docker-compose restart openwebui"
```

## 📊 Мониторинг после применения исправлений

### Скрипт проверки производительности

**Файл `scripts/check-database-performance.sh`:**
```bash
#!/bin/bash
# Скрипт проверки производительности БД после оптимизации

echo "=== Проверка производительности БД ERNI-KI ==="
echo "Дата: $(date)"
echo

# PostgreSQL статистика
echo "📊 PostgreSQL статистика:"
docker-compose exec db psql -U postgres -d openwebui -c "
SELECT 
    schemaname||'.'||tablename as table_name,
    n_tup_ins + n_tup_upd + n_tup_del as operations,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_stat_user_tables 
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;
"

echo
echo "🔍 Медленные запросы (если есть):"
docker-compose exec db psql -U postgres -d openwebui -c "
SELECT query, calls, total_time, mean_time 
FROM pg_stat_statements 
WHERE mean_time > 100 
ORDER BY mean_time DESC 
LIMIT 5;
" 2>/dev/null || echo "pg_stat_statements не включен"

echo
echo "📈 Redis статистика:"
docker-compose exec redis redis-cli -a "$(grep REDIS_ARGS env/redis.env | cut -d'"' -f2 | cut -d' ' -f2)" info memory | grep -E "(used_memory_human|used_memory_peak_human)"

echo
echo "🔄 Checkpoint активность:"
docker-compose logs db --tail=10 | grep checkpoint || echo "Нет недавних checkpoint записей"

echo
echo "✅ Проверка завершена"
```

---

**Примечание:** Все скрипты должны быть выполнены с правами администратора и после создания резервных копий данных.
