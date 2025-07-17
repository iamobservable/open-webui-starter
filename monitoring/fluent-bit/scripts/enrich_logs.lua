-- Lua скрипт для обогащения логов ERNI-KI метаданными
-- Добавляет информацию о сервисах, приоритетах и категориях

function enrich_service_logs(tag, timestamp, record)
    -- Извлечение имени контейнера из тега
    local container_name = ""
    if tag then
        container_name = string.match(tag, "docker%.var%.lib%.docker%.containers%.([^%.]+)")
        if container_name then
            -- Получение первых 12 символов container ID
            container_name = string.sub(container_name, 1, 12)
        end
    end
    
    -- Определение сервиса по имени контейнера или логу
    local service_name = detect_service(record, container_name)
    local service_category = get_service_category(service_name)
    local service_priority = get_service_priority(service_name)
    
    -- Обогащение записи метаданными
    record["service"] = service_name
    record["service_category"] = service_category
    record["service_priority"] = service_priority
    record["container_short_id"] = container_name
    
    -- Добавление информации о кластере
    record["cluster"] = "erni-ki"
    record["environment"] = "production"
    
    -- Парсинг уровня логирования
    local log_level = extract_log_level(record)
    if log_level then
        record["level"] = log_level
        record["level_numeric"] = get_level_numeric(log_level)
    end
    
    -- Добавление тегов для критических ошибок
    if is_critical_error(record) then
        record["alert_required"] = true
        record["severity"] = "critical"
    elseif is_warning(record) then
        record["severity"] = "warning"
    else
        record["severity"] = "info"
    end
    
    -- Добавление метрик производительности
    add_performance_metrics(record, service_name)
    
    return 1, timestamp, record
end

-- Определение сервиса по логам и контейнеру
function detect_service(record, container_name)
    local log_message = record["log"] or record["message"] or ""
    
    -- Проверка по ключевым словам в логах
    if string.find(log_message, "ollama") or string.find(log_message, "llama") then
        return "ollama"
    elseif string.find(log_message, "openwebui") or string.find(log_message, "open-webui") then
        return "openwebui"
    elseif string.find(log_message, "nginx") then
        return "nginx"
    elseif string.find(log_message, "postgres") or string.find(log_message, "postgresql") then
        return "postgres"
    elseif string.find(log_message, "redis") then
        return "redis"
    elseif string.find(log_message, "searxng") then
        return "searxng"
    elseif string.find(log_message, "auth") then
        return "auth"
    elseif string.find(log_message, "cloudflared") then
        return "cloudflared"
    elseif string.find(log_message, "docling") then
        return "docling"
    elseif string.find(log_message, "edgetts") then
        return "edgetts"
    elseif string.find(log_message, "tika") then
        return "tika"
    elseif string.find(log_message, "mcpo") then
        return "mcposerver"
    elseif string.find(log_message, "watchtower") then
        return "watchtower"
    elseif string.find(log_message, "backrest") then
        return "backrest"
    else
        return "unknown"
    end
end

-- Получение категории сервиса
function get_service_category(service_name)
    local categories = {
        ["ollama"] = "ai",
        ["openwebui"] = "ai",
        ["searxng"] = "search",
        ["postgres"] = "database",
        ["redis"] = "cache",
        ["nginx"] = "proxy",
        ["auth"] = "security",
        ["cloudflared"] = "network",
        ["docling"] = "processing",
        ["edgetts"] = "ai",
        ["tika"] = "processing",
        ["mcposerver"] = "ai",
        ["watchtower"] = "infrastructure",
        ["backrest"] = "backup"
    }
    
    return categories[service_name] or "unknown"
end

-- Получение приоритета сервиса
function get_service_priority(service_name)
    local priorities = {
        ["postgres"] = "critical",
        ["nginx"] = "critical",
        ["auth"] = "critical",
        ["ollama"] = "high",
        ["openwebui"] = "high",
        ["redis"] = "medium",
        ["searxng"] = "medium",
        ["cloudflared"] = "medium",
        ["docling"] = "low",
        ["edgetts"] = "low",
        ["tika"] = "low",
        ["mcposerver"] = "low",
        ["watchtower"] = "low",
        ["backrest"] = "medium"
    }
    
    return priorities[service_name] or "low"
end

-- Извлечение уровня логирования
function extract_log_level(record)
    local log_message = record["log"] or record["message"] or ""
    local level_field = record["level"] or record["severity"] or ""
    
    -- Проверка поля level
    if level_field ~= "" then
        return string.upper(level_field)
    end
    
    -- Поиск в сообщении
    local patterns = {
        "FATAL", "CRITICAL", "ERROR", "WARN", "WARNING", "INFO", "DEBUG", "TRACE"
    }
    
    for _, pattern in ipairs(patterns) do
        if string.find(string.upper(log_message), pattern) then
            return pattern
        end
    end
    
    return "INFO"
end

-- Получение числового значения уровня
function get_level_numeric(level)
    local levels = {
        ["FATAL"] = 60,
        ["CRITICAL"] = 50,
        ["ERROR"] = 40,
        ["WARN"] = 30,
        ["WARNING"] = 30,
        ["INFO"] = 20,
        ["DEBUG"] = 10,
        ["TRACE"] = 0
    }
    
    return levels[level] or 20
end

-- Проверка критических ошибок
function is_critical_error(record)
    local log_message = string.upper(record["log"] or record["message"] or "")
    local level = string.upper(record["level"] or "")
    
    -- Критические уровни
    if level == "FATAL" or level == "CRITICAL" or level == "ERROR" then
        return true
    end
    
    -- Критические ключевые слова
    local critical_patterns = {
        "FATAL", "CRITICAL", "EXCEPTION", "PANIC", "SEGFAULT", 
        "OUT OF MEMORY", "DISK FULL", "CONNECTION REFUSED",
        "AUTHENTICATION FAILED", "PERMISSION DENIED", "TIMEOUT",
        "GPU ERROR", "CUDA ERROR", "NVIDIA ERROR"
    }
    
    for _, pattern in ipairs(critical_patterns) do
        if string.find(log_message, pattern) then
            return true
        end
    end
    
    return false
end

-- Проверка предупреждений
function is_warning(record)
    local log_message = string.upper(record["log"] or record["message"] or "")
    local level = string.upper(record["level"] or "")
    
    if level == "WARN" or level == "WARNING" then
        return true
    end
    
    local warning_patterns = {
        "WARN", "WARNING", "DEPRECATED", "SLOW QUERY", "HIGH CPU",
        "HIGH MEMORY", "RETRY", "FALLBACK", "DEGRADED"
    }
    
    for _, pattern in ipairs(warning_patterns) do
        if string.find(log_message, pattern) then
            return true
        end
    end
    
    return false
end

-- Добавление метрик производительности
function add_performance_metrics(record, service_name)
    local log_message = record["log"] or record["message"] or ""
    
    -- Извлечение времени ответа
    local response_time = string.match(log_message, "response_time:(%d+%.?%d*)ms")
    if response_time then
        record["response_time_ms"] = tonumber(response_time)
    end
    
    -- Извлечение статус кода
    local status_code = string.match(log_message, "status:(%d+)")
    if status_code then
        record["status_code"] = tonumber(status_code)
    end
    
    -- Извлечение использования памяти
    local memory_usage = string.match(log_message, "memory:(%d+%.?%d*)MB")
    if memory_usage then
        record["memory_usage_mb"] = tonumber(memory_usage)
    end
    
    -- Извлечение использования GPU
    local gpu_usage = string.match(log_message, "gpu:(%d+%.?%d*)%%")
    if gpu_usage then
        record["gpu_usage_percent"] = tonumber(gpu_usage)
    end
end
