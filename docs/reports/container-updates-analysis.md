# ERNI-KI Container Updates Analysis Report

**Дата:** 29 августа 2025  
**Версия:** 1.0  
**Автор:** Альтэон Шульц, Tech Lead  

## 📊 Исполнительное резюме

Проведен комплексный анализ 26 Docker контейнеров в ERNI-KI системе на предмет доступных обновлений. Выявлены критические обновления, требующие немедленного внимания, и подготовлен поэтапный план внедрения.

### 🎯 Ключевые находки:

- **2 критических обновления** требуют немедленного внимания (Ollama, OpenWebUI)
- **1 major версия** Prometheus (v2.48.0 → v3.5.0) с потенциальными breaking changes
- **8 сервисов** имеют доступные обновления
- **6 сервисов** уже используют актуальные версии

---

## 🔴 Критические обновления (немедленно)

### 1. Ollama: 0.11.6 → 0.11.8
**Приоритет:** КРИТИЧЕСКИЙ  
**Риск:** СРЕДНИЙ  
**Downtime:** < 2 минуты  

**Изменения в v0.11.8 (27 августа 2025):**
- Flash attention включен по умолчанию для `gpt-oss`
- Улучшено время загрузки моделей `gpt-oss`
- Исправления производительности

**Команды обновления:**
```bash
# Backup текущих моделей
docker-compose exec ollama ollama list > ollama-models-backup-$(date +%Y%m%d).txt

# Обновление
docker-compose stop ollama
docker pull ollama/ollama:0.11.8
sed -i 's|ollama/ollama:0.11.6|ollama/ollama:0.11.8|g' compose.yml
docker-compose up -d ollama

# Проверка
docker-compose logs ollama
curl -f http://localhost:11434/api/tags
```

### 2. OpenWebUI: cuda → v0.6.26
**Приоритет:** КРИТИЧЕСКИЙ  
**Риск:** СРЕДНИЙ  
**Downtime:** < 3 минуты  

**Рекомендации:**
- Сделать backup базы данных PostgreSQL
- Проверить changelog на breaking changes
- Тестировать RAG функциональность после обновления

**Команды обновления:**
```bash
# Backup базы данных
docker-compose exec db pg_dump -U postgres openwebui > openwebui-backup-$(date +%Y%m%d).sql

# Обновление
docker-compose stop openwebui
docker pull ghcr.io/open-webui/open-webui:v0.6.26
sed -i 's|ghcr.io/open-webui/open-webui:cuda|ghcr.io/open-webui/open-webui:v0.6.26|g' compose.yml
docker-compose up -d openwebui

# Проверка
docker-compose logs openwebui
curl -f http://localhost:8080/health
```

---

## ⚠️ Major версии (планировать)

### Prometheus: v2.48.0 → v3.5.0
**Приоритет:** ВЫСОКИЙ  
**Риск:** ВЫСОКИЙ  
**Downtime:** < 10 минут  

**⚠️ ВНИМАНИЕ: Major версия с потенциальными breaking changes**

**Подготовка к обновлению:**
1. Изучить [Prometheus 3.0 migration guide](https://prometheus.io/docs/prometheus/latest/migration/)
2. Проверить совместимость конфигурации
3. Тестировать на staging окружении
4. Планировать maintenance window

**НЕ ОБНОВЛЯТЬ без предварительного тестирования!**

---

## 🟡 Рекомендуемые обновления (в течение недели)

### 1. LiteLLM: main-latest → v1.76.0.dev2
**Приоритет:** СРЕДНИЙ  
**Риск:** НИЗКИЙ  

### 2. PostgreSQL Exporter: v0.15.0 → latest
**Приоритет:** СРЕДНИЙ  
**Риск:** НИЗКИЙ  

### 3. Redis Exporter: v1.55.0 → latest
**Приоритет:** НИЗКИЙ  
**Риск:** НИЗКИЙ  

---

## 📋 Поэтапный план обновления

### Фаза 1: Критические обновления (сегодня)
**Время выполнения:** 30 минут  
**Downtime:** < 5 минут  

```bash
#!/bin/bash
# Критические обновления ERNI-KI

set -euo pipefail

echo "=== Фаза 1: Критические обновления ==="

# Создание backup
echo "Создание backup..."
mkdir -p .backups/$(date +%Y%m%d_%H%M%S)
docker-compose exec db pg_dump -U postgres openwebui > .backups/$(date +%Y%m%d_%H%M%S)/openwebui-backup.sql
docker-compose exec ollama ollama list > .backups/$(date +%Y%m%d_%H%M%S)/ollama-models.txt

# Обновление Ollama
echo "Обновление Ollama 0.11.6 → 0.11.8..."
docker-compose stop ollama
docker pull ollama/ollama:0.11.8
sed -i 's|ollama/ollama:0.11.6|ollama/ollama:0.11.8|g' compose.yml
docker-compose up -d ollama
sleep 30

# Проверка Ollama
if curl -f http://localhost:11434/api/tags >/dev/null 2>&1; then
    echo "✅ Ollama обновлен успешно"
else
    echo "❌ Ошибка обновления Ollama"
    exit 1
fi

# Обновление OpenWebUI
echo "Обновление OpenWebUI cuda → v0.6.26..."
docker-compose stop openwebui
docker pull ghcr.io/open-webui/open-webui:v0.6.26
sed -i 's|ghcr.io/open-webui/open-webui:cuda|ghcr.io/open-webui/open-webui:v0.6.26|g' compose.yml
docker-compose up -d openwebui
sleep 60

# Проверка OpenWebUI
if curl -f http://localhost:8080/health >/dev/null 2>&1; then
    echo "✅ OpenWebUI обновлен успешно"
else
    echo "❌ Ошибка обновления OpenWebUI"
    exit 1
fi

echo "✅ Критические обновления завершены!"
```

### Фаза 2: Рекомендуемые обновления (в течение недели)
**Время выполнения:** 20 минут  
**Downtime:** < 2 минуты  

```bash
#!/bin/bash
# Рекомендуемые обновления ERNI-KI

set -euo pipefail

echo "=== Фаза 2: Рекомендуемые обновления ==="

# Обновление LiteLLM
echo "Обновление LiteLLM..."
docker-compose stop litellm
docker pull ghcr.io/berriai/litellm:v1.76.0.dev2
sed -i 's|ghcr.io/berriai/litellm:main-latest|ghcr.io/berriai/litellm:v1.76.0.dev2|g' compose.yml
docker-compose up -d litellm

# Обновление exporters
echo "Обновление exporters..."
docker-compose stop postgres-exporter redis-exporter
docker pull prometheuscommunity/postgres-exporter:latest
docker pull oliver006/redis_exporter:latest
sed -i 's|prometheuscommunity/postgres-exporter:v0.15.0|prometheuscommunity/postgres-exporter:latest|g' compose.yml
sed -i 's|oliver006/redis_exporter:v1.55.0|oliver006/redis_exporter:latest|g' compose.yml
docker-compose up -d postgres-exporter redis-exporter

echo "✅ Рекомендуемые обновления завершены!"
```

### Фаза 3: Планирование Prometheus 3.0 (следующий месяц)
**Время выполнения:** 2-4 часа  
**Downtime:** < 30 минут  

1. **Подготовка (2 недели):**
   - Изучение migration guide
   - Тестирование на staging
   - Подготовка конфигурации

2. **Внедрение (maintenance window):**
   - Backup всех метрик
   - Обновление конфигурации
   - Миграция данных
   - Тестирование алертов

---

## 🔧 Команды для экстренного отката

### Откат Ollama
```bash
docker-compose stop ollama
sed -i 's|ollama/ollama:0.11.8|ollama/ollama:0.11.6|g' compose.yml
docker-compose up -d ollama
```

### Откат OpenWebUI
```bash
docker-compose stop openwebui
sed -i 's|ghcr.io/open-webui/open-webui:v0.6.26|ghcr.io/open-webui/open-webui:cuda|g' compose.yml
docker-compose up -d openwebui

# Восстановление БД при необходимости
# docker-compose exec db psql -U postgres openwebui < .backups/YYYYMMDD_HHMMSS/openwebui-backup.sql
```

---

## 📊 Мониторинг после обновления

### Ключевые метрики для отслеживания:

1. **Ollama производительность:**
   ```bash
   # Время генерации ответа
   curl -X POST http://localhost:11434/api/generate \
     -d '{"model":"llama2","prompt":"Hello","stream":false}' \
     | jq '.eval_duration'
   ```

2. **OpenWebUI доступность:**
   ```bash
   # Health check
   curl -f http://localhost:8080/health
   
   # RAG функциональность
   # Тестировать через веб-интерфейс
   ```

3. **Системные ресурсы:**
   ```bash
   # Использование GPU
   nvidia-smi
   
   # Использование памяти
   docker stats --no-stream
   ```

### Алерты для настройки:

```yaml
# Prometheus alerting rules
groups:
  - name: erni_ki_updates
    rules:
      - alert: ContainerRestartAfterUpdate
        expr: increase(container_start_time_seconds[5m]) > 0
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Container restarted after update"
      
      - alert: HighMemoryUsageAfterUpdate
        expr: container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.9
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High memory usage after container update"
```

---

## 📚 Заключение и рекомендации

### Немедленные действия:
1. ✅ **Обновить Ollama до 0.11.8** (критично для производительности)
2. ✅ **Обновить OpenWebUI до v0.6.26** (новые функции и исправления)
3. ⚠️ **НЕ обновлять Prometheus** без предварительного тестирования

### Долгосрочные рекомендации:
1. **Настроить автоматический мониторинг** обновлений через Watchtower
2. **Создать staging окружение** для тестирования обновлений
3. **Документировать процедуры** обновления для каждого сервиса
4. **Планировать регулярные** maintenance windows

### Следующие шаги:
1. Выполнить критические обновления (сегодня)
2. Запланировать рекомендуемые обновления (эта неделя)
3. Подготовить план миграции Prometheus 3.0 (следующий месяц)
4. Настроить автоматизированный мониторинг обновлений

**Система готова к безопасному обновлению критических компонентов!** 🚀
