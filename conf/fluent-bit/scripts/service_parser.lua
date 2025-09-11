-- ============================================================================
-- Fluent Bit Lua Script - Service Name Parser для ERNI-KI
-- Цель: Извлечение чистого имени сервиса из container_name
-- ============================================================================
-- Версия: 1.0.0
-- Создано: 2025-09-01
-- Назначение: Парсинг имен сервисов для лучшей категоризации логов
-- ============================================================================

function parse_service_name(tag, timestamp, record)
    -- Получаем исходное имя контейнера
    local service_raw = record["service_raw"]
    
    if service_raw == nil then
        record["service"] = "unknown"
        return 1, timestamp, record
    end
    
    -- Убираем префикс "erni-ki-" и суффикс "-1", "-2" и т.д.
    local service_name = string.gsub(service_raw, "^erni%-ki%-", "")
    service_name = string.gsub(service_name, "%-[0-9]+$", "")
    
    -- Маппинг специальных случаев
    local service_mapping = {
        ["db"] = "postgres",
        ["mcposerver"] = "mcp",
        ["fluent-bit"] = "logging",
        ["nginx-exporter"] = "nginx-metrics",
        ["redis-exporter"] = "redis-metrics",
        ["postgres-exporter"] = "postgres-metrics",
        ["ollama-exporter"] = "ollama-metrics",
        ["nvidia-exporter"] = "gpu-metrics",
        ["node-exporter"] = "system-metrics",
        ["blackbox-exporter"] = "network-metrics",
        ["webhook-receiver"] = "webhooks"
    }
    
    -- Применяем маппинг если есть
    if service_mapping[service_name] then
        service_name = service_mapping[service_name]
    end
    
    -- Устанавливаем финальное имя сервиса
    record["service"] = service_name
    
    -- Добавляем категорию сервиса для лучшей группировки
    local service_categories = {
        ["nginx"] = "web",
        ["openwebui"] = "web",
        ["ollama"] = "ai",
        ["litellm"] = "ai",
        ["postgres"] = "database",
        ["redis"] = "database",
        ["searxng"] = "search",
        ["prometheus"] = "monitoring",
        ["grafana"] = "monitoring",
        ["loki"] = "monitoring",
        ["alertmanager"] = "monitoring",
        ["logging"] = "infrastructure",
        ["cloudflared"] = "infrastructure",
        ["watchtower"] = "infrastructure",
        ["backrest"] = "backup",
        ["auth"] = "security",
        ["mcp"] = "integration",
        ["docling"] = "processing",
        ["tika"] = "processing",
        ["edgetts"] = "processing"
    }
    
    -- Добавляем категорию
    record["service_category"] = service_categories[service_name] or "other"
    
    -- Добавляем метрики для мониторинга
    if string.find(service_name, "metrics") then
        record["service_category"] = "metrics"
        record["is_metrics"] = true
    else
        record["is_metrics"] = false
    end
    
    return 1, timestamp, record
end
