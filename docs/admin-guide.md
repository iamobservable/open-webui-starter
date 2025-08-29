# 👨‍💼 Administration Guide - ERNI-KI

> **Версия:** 6.0 **Дата обновления:** 25.08.2025 **Статус:** Production Ready (Оптимизированные
> PostgreSQL и Redis + Enterprise мониторинг + Troubleshooting)

## 📋 Обзор

Comprehensive руководство по администрированию и мониторингу системы ERNI-KI с оптимизированной
архитектурой 15+ сервисов, enterprise-grade производительностью БД и полным мониторингом стеком в
production окружении.

## 🚀 Production оптимизации (август 2025)

#### 🔴 Критические оптимизации БД

- ✅ **PostgreSQL 15.13**: Production конфигурация (shared_buffers: 256MB, max_connections: 200)
- ✅ **Redis 7.4.5**: Memory limits (2GB) с LRU eviction policy
- ✅ **Cache hit ratio**: 99.76% для PostgreSQL (отличная производительность)
- ✅ **Memory overcommit**: Исправлен warning (vm.overcommit_memory=1)

#### 🛡️ Security & Performance

- ✅ **Security Headers**: X-Frame-Options, X-XSS-Protection, HSTS
- ✅ **Gzip сжатие**: 60-80% экономия трафика
- ✅ **SearXNG кэширование**: 1000ms → 1ms (930x улучшение)
- ✅ **PostgreSQL логирование**: Connection/disconnection/slow queries

#### 📊 Enterprise мониторинг

- ✅ **Database Monitoring**: PostgreSQL и Redis exporters
- ✅ **Troubleshooting документация**: Полные процедуры диагностики
- ✅ **Performance Tracking**: Real-time метрики производительности БД

## 🔧 Ежедневное администрирование

### Утренняя проверка системы

```bash
# Проверка здоровья всех сервисов
./scripts/maintenance/health-check.sh

# Быстрый аудит системы
./scripts/maintenance/quick-audit.sh

# Проверка веб-интерфейсов
./scripts/maintenance/check-web-interfaces.sh
```

### Мониторинг ресурсов

```bash
# Мониторинг системы
./scripts/performance/system-health-monitor.sh

# Мониторинг GPU (если доступно)
./scripts/performance/gpu-monitor.sh

# Проверка использования дисков
df -h
```

## 📊 Система мониторинга

### Grafana Dashboard

- **URL:** https://your-domain/grafana
- **Логин:** admin / admin (изменить при первом входе)

**Основные dashboard:**

- **System Overview** - общий обзор системы
- **Docker Containers** - мониторинг контейнеров
- **GPU Metrics** - метрики GPU (если доступно)
- **Application Metrics** - метрики приложений

### Prometheus Metrics

- **URL:** https://your-domain/prometheus
- **Основные метрики:**
  - `container_cpu_usage_seconds_total` - использование CPU
  - `container_memory_usage_bytes` - использование памяти
  - `nvidia_gpu_utilization_percent` - использование GPU
  - `ollama_models_total` - количество AI моделей
  - `ollama_model_size_bytes` - размеры AI моделей
  - `nginx_connections_active` - активные nginx соединения

### AlertManager

- **URL:** https://your-domain/alertmanager
- **Настройка алертов:** `conf/alertmanager/alertmanager.yml`

### 🤖 AI Metrics (Ollama Exporter)

- **URL:** http://localhost:9778/metrics
- **Порт:** 9778
- **Функции:**
  - Мониторинг AI моделей: `ollama_models_total`
  - Размеры моделей: `ollama_model_size_bytes{model="model_name"}`
  - Версия Ollama: `ollama_info{version="x.x.x"}`
  - Статус GPU использования для AI

**Проверка метрик:**

```bash
# Проверка доступности ollama-exporter
curl http://localhost:9778/metrics | grep ollama

# Просмотр AI моделей
curl -s http://localhost:9778/metrics | grep ollama_models_total

# Размеры моделей
curl -s http://localhost:9778/metrics | grep ollama_model_size_bytes
```

### 🌐 Web Analytics (Nginx Exporter)

- **URL:** http://localhost:9113/metrics
- **Порт:** 9113
- **Функции:**
  - HTTP метрики веб-сервера
  - Активные соединения: `nginx_connections_active`
  - Статистика запросов: `nginx_http_requests_total`
  - Производительность upstream'ов

**Проверка метрик:**

```bash
# Проверка доступности nginx-exporter
curl http://localhost:9113/metrics | grep nginx

# Активные соединения
curl -s http://localhost:9113/metrics | grep nginx_connections_active

# Статистика запросов
curl -s http://localhost:9113/metrics | grep nginx_http_requests_total
```

### 📝 Centralized Logging (Fluent-bit + Loki)

- **Fluent-bit метрики:** http://localhost:2020/api/v1/metrics/prometheus
- **Loki:** http://localhost:3100
- **Функции:**
  - Сбор логов всех 29 сервисов ERNI-KI
  - Парсинг и фильтрация логов
  - Отправка в Loki для агрегации
  - Интеграция с Grafana для визуализации
  - Эффективное сжатие и retention политики

**Проверка логирования:**

```bash
# Статус Fluent-bit
curl http://localhost:2020/api/v1/metrics/prometheus | grep fluentbit

# Проверка Loki
curl http://localhost:3100/ready

# Просмотр метрик Loki
curl http://localhost:3100/metrics
curl http://localhost:9200/_cat/indices
```

### 📊 Database Monitoring (Production Ready)

#### PostgreSQL Monitoring

- **PostgreSQL Exporter**: Порт 9187
- **Ключевые метрики**:
  - `pg_up` - доступность PostgreSQL
  - `pg_stat_activity_count` - активные подключения
  - `pg_stat_database_blks_hit` / `pg_stat_database_blks_read` - cache hit ratio
  - `pg_locks_count` - количество блокировок

**Проверка метрик PostgreSQL:**

```bash
# Проверка доступности PostgreSQL exporter
curl -s http://localhost:9187/metrics | grep pg_up

# Cache hit ratio (должен быть >95%)
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "
SELECT round(sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) * 100, 2) as cache_hit_ratio_percent
FROM pg_statio_user_tables;"

# Активные подключения
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "SELECT count(*) FROM pg_stat_activity;"

# Размер БД
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "SELECT pg_size_pretty(pg_database_size('openwebui'));"
```

#### Redis Monitoring

- **Redis Exporter**: Порт 9121
- **Ключевые метрики**:
  - `redis_up` - доступность Redis
  - `redis_memory_used_bytes` - использование памяти
  - `redis_connected_clients` - подключенные клиенты
  - `redis_keyspace_hits_total` / `redis_keyspace_misses_total` - hit ratio

**Проверка метрик Redis:**

```bash
# Проверка доступности Redis exporter
curl -s http://localhost:9121/metrics | grep redis_up

# Использование памяти
docker exec erni-ki-redis-1 redis-cli INFO memory | grep used_memory_human

# Hit ratio (должен быть >90%)
docker exec erni-ki-redis-1 redis-cli INFO stats | grep keyspace

# Количество ключей
docker exec erni-ki-redis-1 redis-cli DBSIZE
```

#### Database Performance Alerts

**Критические алерты (требуют немедленного внимания):**

- PostgreSQL недоступен более 30 секунд
- Cache hit ratio PostgreSQL < 95%
- Redis недоступен более 30 секунд
- Использование памяти Redis > 80% от лимита

**Предупреждающие алерты:**

- Активные подключения PostgreSQL > 80% от max_connections
- Медленные запросы PostgreSQL > 100ms
- Redis evicted keys > 0

## 💾 Управление backup

### ✅ Новые возможности (август 2025)

**Backrest API endpoints настроены и протестированы:**

- `/v1.Backrest/Backup` - создание резервной копии
- `/v1.Backrest/GetOperations` - получение истории операций

### Ежедневные backup

```bash
# Проверка статуса backup
./scripts/backup/check-local-backup.sh

# Ручной запуск backup через API
curl -X POST "http://localhost:9898/v1.Backrest/Backup" \
  -H "Content-Type: application/json" \
  -d '{"value": "daily"}'

# Проверка истории операций
curl -X POST "http://localhost:9898/v1.Backrest/GetOperations" \
  -H "Content-Type: application/json" \
  -d '{}'

# Традиционный способ через скрипт
./scripts/backup/backrest-management.sh backup
```

### Восстановление из backup

```bash
# Список доступных backup
./scripts/backup/backrest-management.sh list

# Восстановление конкретного backup
./scripts/backup/backrest-management.sh restore --date=2025-08-22

# Тестовое восстановление
./scripts/backup/backrest-management.sh test-restore
```

### Snapshot конфигураций

```bash
# Создание snapshot перед обновлениями
BACKUP_DIR=".config-backup/pre-update-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -r env/ conf/ compose.yml "$BACKUP_DIR/"
```

## 🔄 Управление сервисами

### Основные команды Docker Compose

```bash
# Просмотр статуса всех сервисов
docker compose ps

# Просмотр логов
docker compose logs -f [service-name]

# Перезапуск сервиса
docker compose restart [service-name]

# Обновление сервиса
docker compose pull [service-name]
docker compose up -d [service-name]
```

### Управление Ollama

```bash
# Просмотр доступных моделей
docker compose exec ollama ollama list

# Загрузка новой модели
docker compose exec ollama ollama pull llama2

# Удаление модели
docker compose exec ollama ollama rm model-name
```

### Управление PostgreSQL

```bash
# Подключение к базе данных
docker compose exec db psql -U postgres -d openwebui

# Создание backup базы данных
docker compose exec db pg_dump -U postgres openwebui > backup.sql

# Восстановление базы данных
docker compose exec -T postgres psql -U postgres openwebui < backup.sql
```

## 📝 Управление логами

### Просмотр логов

```bash
# Логи всех сервисов
docker compose logs -f

# Логи конкретного сервиса
docker compose logs -f openwebui

# Логи с фильтрацией по времени
docker compose logs --since="1h" --until="30m"
```

### Ротация логов

```bash
# Автоматическая ротация логов
./scripts/maintenance/log-rotation-manager.sh

# Настройка ротации логов
./scripts/setup/setup-log-rotation.sh

# Очистка старых логов
./scripts/security/rotate-logs.sh
```

## 🔒 Управление безопасностью

### Мониторинг безопасности

```bash
# Проверка безопасности системы
./scripts/security/security-monitor.sh

# Аудит конфигураций безопасности
./scripts/security/security-hardening.sh --audit

# Ротация секретов
./scripts/security/rotate-secrets.sh
```

### Управление SSL сертификатами

```bash
# Проверка срока действия сертификатов
openssl x509 -in conf/ssl/cert.pem -text -noout | grep "Not After"

# Обновление сертификатов
./conf/ssl/generate-ssl-certs.sh

# Перезагрузка nginx после обновления
docker compose restart nginx
```

## ⚡ Оптимизация производительности

### Мониторинг производительности

```bash
# Быстрый тест производительности
./scripts/performance/quick-performance-test.sh

# Тест производительности GPU
./scripts/performance/gpu-performance-test.sh

# Нагрузочное тестирование
./scripts/performance/load-testing.sh
```

### Оптимизация ресурсов

```bash
# Оптимизация сети
./scripts/maintenance/optimize-network.sh

# Оптимизация SearXNG
./scripts/maintenance/optimize-searxng.sh

# Анализ использования ресурсов
./scripts/performance/hardware-analysis.sh
```

## 🔧 Обслуживание системы

### Еженедельные задачи

```bash
# Полный аудит системы
./scripts/maintenance/comprehensive-audit.sh

# Очистка неиспользуемых Docker образов
docker system prune -f

# Проверка обновлений
docker compose pull
```

### Ежемесячные задачи

```bash
# Обновление системы
sudo apt update && sudo apt upgrade

# Проверка дискового пространства
./scripts/performance/hardware-analysis.sh

# Архивирование старых логов
./scripts/maintenance/log-rotation-manager.sh --archive
```

## 🚨 Аварийное восстановление

### Автоматическое восстановление

```bash
# Запуск автоматического восстановления
./scripts/troubleshooting/automated-recovery.sh

# Исправление критических проблем
./scripts/troubleshooting/fix-critical-issues.sh

# Исправление нездоровых сервисов
./scripts/troubleshooting/fix-unhealthy-services.sh
```

### Ручное восстановление

```bash
# Корректный перезапуск системы
./scripts/maintenance/graceful-restart.sh

# Восстановление из backup
./scripts/backup/backrest-management.sh restore

# Проверка целостности данных
./scripts/troubleshooting/test-healthcheck.sh
```

## 📈 Масштабирование

### Горизонтальное масштабирование

```bash
# Добавление дополнительных worker'ов
docker compose up -d --scale openwebui=3

# Настройка load balancer
nano conf/nginx/nginx.conf
```

### Вертикальное масштабирование

```bash
# Увеличение ресурсов для сервисов
nano compose.yml
# Изменить memory и cpu limits

# Применение изменений
docker compose up -d
```

## 🔍 Диагностика проблем

### Общая диагностика

```bash
# Проверка статуса всех сервисов
docker compose ps

# Проверка использования ресурсов
docker stats

# Проверка сетевых подключений
docker network ls
```

### Специфичная диагностика

```bash
# Диагностика Ollama
./scripts/troubleshooting/test-healthcheck.sh

# Диагностика SearXNG
./scripts/troubleshooting/test-searxng-integration.sh

# Диагностика сети
./scripts/troubleshooting/test-network-simple.sh
```

## 📞 Контакты и поддержка

### Внутренние ресурсы

- **Мониторинг:** https://your-domain/grafana
- **Логи:** https://your-domain/kibana
- **Метрики:** https://your-domain/prometheus

### Внешние ресурсы

- **📖 Документация:** [docs/troubleshooting.md](troubleshooting.md)
- **🔧 Database Troubleshooting:** [docs/database-troubleshooting.md](database-troubleshooting.md)
- **📊 Database Monitoring:** [docs/database-monitoring-plan.md](database-monitoring-plan.md)
- **⚡ Production Optimizations:**
  [docs/database-production-optimizations.md](database-production-optimizations.md)
- **🐛 Issues:** [GitHub Issues](https://github.com/DIZ-admin/erni-ki/issues)
- **💬 Discussions:** [GitHub Discussions](https://github.com/DIZ-admin/erni-ki/discussions)

## ✅ Процедуры валидации системы

### Критерии успеха после обновлений

```bash
# 1. Проверка статуса всех сервисов
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(healthy|Up)" | wc -l
# Ожидаемый результат: 29+ сервисов

# 2. Проверка Cloudflare туннеля (отсутствие DNS ошибок)
docker logs --since=5m erni-ki-cloudflared-1 2>&1 | grep -E "(ERROR|ERR)" | wc -l
# Ожидаемый результат: 0

# 3. Проверка SearXNG API производительности
time curl -s "http://localhost:8080/api/searxng/search?q=test&format=json" | jq '.results | length'
# Ожидаемый результат: <2s, 40+ результатов

# 4. Проверка Backrest API
curl -X POST "http://localhost:9898/v1.Backrest/GetOperations" -H "Content-Type: application/json" -d '{}' -s | jq 'has("operations")'
# Ожидаемый результат: true или false (API отвечает)

# 5. Проверка GPU Ollama
docker exec erni-ki-ollama-1 nvidia-smi -L | grep -c "GPU"
# Ожидаемый результат: 1

# 6. Проверка OpenWebUI доступности
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health
# Ожидаемый результат: 200
```

### Rollback процедуры

```bash
# 1. Остановка сервисов
docker compose down

# 2. Восстановление конфигураций из snapshot
cp -r .config-backup/pre-update-YYYYMMDD-HHMMSS/* .

# 3. Запуск предыдущей версии
docker compose up -d

# 4. Проверка критических сервисов
./scripts/maintenance/health-check.sh

# Время выполнения: 5-10 минут
```

---

**📝 Примечание:** Данное руководство актуализировано для архитектуры 29 сервисов ERNI-KI версии 5.1
(август 2025).
