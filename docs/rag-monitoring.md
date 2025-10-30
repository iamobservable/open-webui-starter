# RAG System Monitoring Guide

**Дата создания**: 2025-10-24  
**Версия**: 1.0  
**Автор**: Augment Agent

---

## Обзор

Система мониторинга RAG (Retrieval-Augmented Generation) для ERNI-KI
обеспечивает:

- Проверку здоровья всех RAG компонентов
- Измерение производительности ключевых операций
- Автоматические уведомления при проблемах
- Логирование метрик для анализа

---

## Компоненты Мониторинга

### 1. RAG Health Monitor (`scripts/rag-health-monitor.sh`)

Основной скрипт для проверки здоровья RAG системы.

**Проверяемые компоненты**:

- ✅ OpenWebUI (статус healthy)
- ✅ SearXNG (производительность <2s)
- ✅ PostgreSQL/pgvector (производительность <100ms)
- ✅ Ollama (наличие embedding модели)
- ✅ Docling (доступность сервиса)
- ✅ Nginx (кэширование)

**Использование**:

```bash
# Ручной запуск
./scripts/rag-health-monitor.sh

# Вывод логируется в logs/rag-health-YYYYMMDD.log
```

**Пороговые значения**:

- SearXNG response time: <2000ms
- pgvector query time: <100ms
- Ollama embedding: <2000ms
- Docling processing: <5000ms

**Выходные коды**:

- `0` - Все проверки пройдены (RAG system healthy)
- `1` - Обнаружены проблемы (RAG system has issues)

---

### 2. Webhook Notifications (`scripts/rag-webhook-notify.sh`)

Отправка уведомлений о состоянии RAG системы через webhook (Discord/Slack).

**Настройка**:

```bash
# Включение webhook уведомлений
export RAG_WEBHOOK_ENABLED=true
export RAG_WEBHOOK_URL="https://discord.com/api/webhooks/YOUR_WEBHOOK_URL"

# Или добавить в env/monitoring.env
echo "RAG_WEBHOOK_ENABLED=true" >> env/monitoring.env
echo "RAG_WEBHOOK_URL=https://discord.com/api/webhooks/..." >> env/monitoring.env
```

**Использование**:

```bash
# Отправка уведомления
./scripts/rag-webhook-notify.sh "healthy" "RAG system is operational" "All checks passed"
./scripts/rag-webhook-notify.sh "warning" "SearXNG slow response" "Response time: 3500ms"
./scripts/rag-webhook-notify.sh "error" "pgvector unavailable" "Database connection failed"
```

**Типы статусов**:

- `healthy` - ✅ Зелёный (всё работает)
- `warning` - ⚠️ Жёлтый (деградация производительности)
- `error` - ❌ Красный (критическая ошибка)

---

## Автоматический Мониторинг

### Настройка Cron

Для автоматической проверки каждые 5 минут:

```bash
# Редактировать crontab
crontab -e

# Добавить строку (проверка каждые 5 минут)
*/5 * * * * cd /home/konstantin/Documents/augment-projects/erni-ki && ./scripts/rag-health-monitor.sh >> logs/rag-health-cron.log 2>&1

# Уведомление при ошибках (каждые 15 минут)
*/15 * * * * cd /home/konstantin/Documents/augment-projects/erni-ki && ./scripts/rag-health-monitor.sh || ./scripts/rag-webhook-notify.sh "error" "RAG health check failed" "Check logs/rag-health-$(date +\%Y\%m\%d).log"
```

### Systemd Timer (альтернатива cron)

Создать systemd service и timer для более надёжного мониторинга:

```bash
# /etc/systemd/system/rag-health-monitor.service
[Unit]
Description=ERNI-KI RAG Health Monitor
After=docker.service

[Service]
Type=oneshot
WorkingDirectory=/home/konstantin/Documents/augment-projects/erni-ki
ExecStart=/home/konstantin/Documents/augment-projects/erni-ki/scripts/rag-health-monitor.sh
User=konstantin
StandardOutput=append:/home/konstantin/Documents/augment-projects/erni-ki/logs/rag-health-systemd.log
StandardError=append:/home/konstantin/Documents/augment-projects/erni-ki/logs/rag-health-systemd.log

[Install]
WantedBy=multi-user.target
```

```bash
# /etc/systemd/system/rag-health-monitor.timer
[Unit]
Description=ERNI-KI RAG Health Monitor Timer
Requires=rag-health-monitor.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
Unit=rag-health-monitor.service

[Install]
WantedBy=timers.target
```

```bash
# Активация
sudo systemctl daemon-reload
sudo systemctl enable rag-health-monitor.timer
sudo systemctl start rag-health-monitor.timer

# Проверка статуса
sudo systemctl status rag-health-monitor.timer
```

---

## Метрики и Логи

### Лог Файлы

**Расположение**: `logs/`

- `rag-health-YYYYMMDD.log` - Ежедневные логи health checks
- `rag-health-cron.log` - Логи cron запусков
- `rag-health-systemd.log` - Логи systemd запусков

**Формат логов**:

```
[2025-10-24 15:38:50] === RAG Health Check Started ===
[2025-10-24 15:38:50] SearXNG: 6ms - OK
[2025-10-24 15:38:50] pgvector: 1ms - OK
[2025-10-24 15:38:50] Ollama: nomic-embed model available
[2025-10-24 15:38:50] Docling: 0ms - OK
[2025-10-24 15:38:52] Nginx caching: 138x speedup
[2025-10-24 15:38:52] === RAG Health Check: PASSED ===
```

### Анализ Логов

```bash
# Последние 50 записей
tail -50 logs/rag-health-$(date +%Y%m%d).log

# Поиск ошибок
grep "FAILED\|ERROR\|SLOW" logs/rag-health-*.log

# Статистика производительности SearXNG
grep "SearXNG:" logs/rag-health-*.log | awk '{print $3}' | sed 's/ms//' | sort -n

# Статистика производительности pgvector
grep "pgvector:" logs/rag-health-*.log | awk '{print $3}' | sed 's/ms//' | sort -n
```

---

## Интеграция с Prometheus/Grafana

Для расширенного мониторинга можно интегрировать с Prometheus:

### Node Exporter Textfile Collector

```bash
# Создать скрипт экспорта метрик
cat > scripts/rag-metrics-exporter.sh << 'EOF'
#!/bin/bash
METRICS_FILE="/var/lib/node_exporter/textfile_collector/rag_metrics.prom"

# Запуск health monitor и парсинг результатов
./scripts/rag-health-monitor.sh > /tmp/rag-health-output.txt 2>&1
EXIT_CODE=$?

# Экспорт метрик в Prometheus формате
cat > "$METRICS_FILE" << PROM
# HELP rag_health_status RAG system health status (1=healthy, 0=unhealthy)
# TYPE rag_health_status gauge
rag_health_status{component="overall"} $([ $EXIT_CODE -eq 0 ] && echo 1 || echo 0)

# HELP rag_searxng_response_time_ms SearXNG response time in milliseconds
# TYPE rag_searxng_response_time_ms gauge
rag_searxng_response_time_ms $(grep "SearXNG:" /tmp/rag-health-output.txt | awk '{print $3}' | sed 's/ms//' || echo 0)

# HELP rag_pgvector_query_time_ms pgvector query time in milliseconds
# TYPE rag_pgvector_query_time_ms gauge
rag_pgvector_query_time_ms $(grep "pgvector:" /tmp/rag-health-output.txt | awk '{print $3}' | sed 's/ms//' || echo 0)

# HELP rag_chunks_total Total number of chunks in pgvector
# TYPE rag_chunks_total gauge
rag_chunks_total $(grep "Total Chunks:" /tmp/rag-health-output.txt | awk '{print $3}' || echo 0)

# HELP rag_collections_total Total number of collections in pgvector
# TYPE rag_collections_total gauge
rag_collections_total $(grep "Collections:" /tmp/rag-health-output.txt | awk '{print $2}' || echo 0)
PROM
EOF

chmod +x scripts/rag-metrics-exporter.sh
```

---

## Troubleshooting

### Проблема: SearXNG медленный ответ (>2s)

**Диагностика**:

```bash
# Проверить логи SearXNG
docker logs --tail 100 erni-ki-searxng-1

# Проверить rate limiting
docker logs --tail 100 erni-ki-nginx-1 | grep "limiting requests"

# Проверить Redis кэш
docker exec erni-ki-redis-1 redis-cli INFO stats
```

**Решение**:

- Увеличить timeout в `env/searxng.env`
- Проверить доступность поисковых движков
- Очистить Redis кэш: `docker exec erni-ki-redis-1 redis-cli FLUSHDB`

---

### Проблема: pgvector медленные запросы (>100ms)

**Диагностика**:

```bash
# Проверить размер таблицы
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "SELECT pg_size_pretty(pg_total_relation_size('document_chunk'));"

# Проверить индексы
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "\d document_chunk"

# Анализ производительности
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "EXPLAIN ANALYZE SELECT * FROM document_chunk LIMIT 10;"
```

**Решение**:

- Выполнить VACUUM ANALYZE:
  `docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "VACUUM ANALYZE document_chunk;"`
- Пересоздать индексы (см. Фаза 2.3)

---

### Проблема: Ollama embedding модель недоступна

**Диагностика**:

```bash
# Проверить список моделей
docker exec erni-ki-ollama-1 ollama list

# Проверить логи Ollama
docker logs --tail 50 erni-ki-ollama-1
```

**Решение**:

```bash
# Загрузить модель заново
docker exec erni-ki-ollama-1 ollama pull nomic-embed-text:latest
```

---

## Best Practices

1. **Регулярный мониторинг**: Запускать health check минимум каждые 5-15 минут
2. **Логирование**: Хранить логи минимум 30 дней для анализа трендов
3. **Уведомления**: Настроить webhook для критических ошибок
4. **Baseline метрики**: Записать нормальные значения производительности
5. **Алерты**: Настроить алерты при превышении порогов на 50%+

---

## Контакты

**Администратор системы**: Kostiantyn Konstantinov  
**Email**: kostiantyn.konstantinov@erni-gruppe.ch  
**Teams**: Доступен для вопросов

---

**Последнее обновление**: 2025-10-24  
**Версия документа**: 1.0
