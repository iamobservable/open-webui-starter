# Grafana Data Sources Configuration - ERNI-KI

## Обзор источников данных

Система мониторинга ERNI-KI использует 3 основных источника данных в Grafana:

### 1. Prometheus (ID: 1) ✅
- **URL**: http://prometheus:9090
- **Тип**: prometheus
- **Статус**: Активен (35 метрик)
- **Назначение**: Сбор и хранение метрик системы
- **Конфигурация**: conf/grafana/provisioning/datasources/prometheus.yml

**Основные метрики:**
- `up` - статус сервисов
- `ollama_*` - метрики AI сервиса Ollama
- `nginx_*` - метрики веб-сервера
- `node_*` - системные метрики
- `pg_*` - метрики PostgreSQL

### 2. Loki (ID: 4) ✅
- **URL**: http://loki:3100
- **Тип**: loki
- **Статус**: Активен (ready)
- **Назначение**: Сбор и хранение логов системы
- **Интеграция**: Fluent Bit → Loki

**Источники логов:**
- nginx (веб-сервер)
- openwebui (AI интерфейс)
- ollama (AI движок)
- searxng (поисковый движок)
- postgres (база данных)

### 3. Alertmanager (ID: 2) ✅
- **URL**: http://alertmanager:9093
- **Тип**: alertmanager
- **Статус**: Активен (success)
- **Назначение**: Управление алертами и уведомлениями
- **Интеграция**: Prometheus → Alertmanager

## Удаленные источники данных

### Elasticsearch (удален 25.08.2025)
- **Причина удаления**: Не используется в текущей архитектуре
- **Замена**: Loki для логирования
- **Статус**: Успешно удален

## Конфигурация

### Автоматическое провижионирование
Источники данных настраиваются автоматически через:
```
conf/grafana/provisioning/datasources/prometheus.yml
```

### Ручная настройка
Дополнительные источники данных можно добавить через:
- Grafana UI: Configuration → Data Sources
- API: POST /api/datasources

## Мониторинг и диагностика

### Проверка статуса
```bash
# Prometheus
curl "http://localhost:3000/api/datasources/proxy/1/api/v1/query?query=up"

# Loki
curl "http://localhost:3000/api/datasources/proxy/4/ready"

# Alertmanager
curl "http://localhost:3000/api/datasources/proxy/2/api/v1/status"
```

### Типичные проблемы
1. **Connection refused**: Проверить статус контейнеров
2. **Timeout**: Увеличить timeout в конфигурации
3. **Authentication**: Проверить credentials

## Обновлено
- **Дата**: 25 августа 2025
- **Версия**: 2.0
- **Автор**: ERNI-KI System Administrator
