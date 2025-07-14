-- Анализ настроек OpenWebUI в базе данных PostgreSQL
-- Скрипт для получения конфигурационных данных

-- 1. Получить все настройки из таблицы config
\echo '=== НАСТРОЙКИ OPENWEBUI ==='
SELECT 
    id as setting_key,
    CASE 
        WHEN LENGTH(data::text) > 100 THEN LEFT(data::text, 100) || '...'
        ELSE data::text
    END as setting_value,
    created_at,
    updated_at
FROM config 
ORDER BY id;

-- 2. Получить настройки RAG и эмбеддингов
\echo ''
\echo '=== RAG И ЭМБЕДДИНГИ ==='
SELECT 
    id as setting_key,
    data::text as setting_value
FROM config 
WHERE id LIKE '%rag%' OR id LIKE '%embedding%' OR id LIKE '%vector%'
ORDER BY id;

-- 3. Получить настройки моделей
\echo ''
\echo '=== НАСТРОЙКИ МОДЕЛЕЙ ==='
SELECT 
    id as setting_key,
    data::text as setting_value
FROM config 
WHERE id LIKE '%model%' OR id LIKE '%ollama%' OR id LIKE '%openai%'
ORDER BY id;

-- 4. Получить настройки интерфейса
\echo ''
\echo '=== НАСТРОЙКИ ИНТЕРФЕЙСА ==='
SELECT 
    id as setting_key,
    data::text as setting_value
FROM config 
WHERE id LIKE '%ui%' OR id LIKE '%theme%' OR id LIKE '%interface%'
ORDER BY id;

-- 5. Получить настройки безопасности
\echo ''
\echo '=== НАСТРОЙКИ БЕЗОПАСНОСТИ ==='
SELECT 
    id as setting_key,
    data::text as setting_value
FROM config 
WHERE id LIKE '%auth%' OR id LIKE '%security%' OR id LIKE '%permission%'
ORDER BY id;

-- 6. Статистика по таблице config
\echo ''
\echo '=== СТАТИСТИКА НАСТРОЕК ==='
SELECT 
    COUNT(*) as total_settings,
    COUNT(CASE WHEN data IS NOT NULL THEN 1 END) as configured_settings,
    COUNT(CASE WHEN data IS NULL THEN 1 END) as empty_settings,
    MIN(created_at) as first_setting_created,
    MAX(updated_at) as last_setting_updated
FROM config;

-- 7. Размер данных конфигурации
\echo ''
\echo '=== РАЗМЕР ДАННЫХ КОНФИГУРАЦИИ ==='
SELECT 
    pg_size_pretty(pg_total_relation_size('config')) as table_size,
    pg_size_pretty(pg_relation_size('config')) as data_size,
    pg_size_pretty(pg_indexes_size('config')) as index_size,
    (SELECT COUNT(*) FROM config) as record_count;

-- 8. Последние изменения настроек
\echo ''
\echo '=== ПОСЛЕДНИЕ ИЗМЕНЕНИЯ ==='
SELECT 
    id as setting_key,
    CASE 
        WHEN LENGTH(data::text) > 50 THEN LEFT(data::text, 50) || '...'
        ELSE data::text
    END as setting_value,
    updated_at
FROM config 
WHERE updated_at IS NOT NULL
ORDER BY updated_at DESC
LIMIT 10;
