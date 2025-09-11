# 📦 Installation Guide - ERNI-KI

> **Версия:** 6.0 **Дата обновления:** 25.08.2025 **Статус:** Production Ready
> (Оптимизированные PostgreSQL и Redis + Security headers + Performance tuning)

## 📋 Обзор

Детальное руководство по установке и настройке системы ERNI-KI -
Production-Ready AI Platform с архитектурой 29 микросервисов и enterprise-grade
производительностью БД.

## 📋 Системные требования

### Минимальные требования

- **OS:** Linux (Ubuntu 20.04+ / CentOS 8+ / Debian 11+)
- **CPU:** 4 cores (8+ рекомендуется)
- **RAM:** 16GB (оптимизировано для PostgreSQL и Redis)
- **Storage:** 100GB свободного места (SSD рекомендуется)
- **Network:** Стабильное интернет-соединение
- **Системные настройки:** vm.overcommit_memory=1 (для Redis)

### Рекомендуемые требования (Production)

- **CPU:** 8+ cores с поддержкой AVX2
- **RAM:** 32GB+ (PostgreSQL: 256MB shared_buffers, Redis: 2GB limit)
- **GPU:** NVIDIA GPU с 8GB+ VRAM (для Ollama GPU ускорения)
- **Storage:** 500GB+ NVMe SSD
- **Network:** 1Gbps+ для быстрой загрузки моделей
- **Мониторинг:** Prometheus + Grafana для метрик БД

## 🔧 Предварительная настройка

### 1. Установка Docker

```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Перезагрузка для применения изменений
sudo reboot
```

### 2. Установка Docker Compose v2

```bash
# Установка Docker Compose v2
sudo apt update
sudo apt install docker-compose-plugin

# Проверка версии
docker compose version
```

### 3. Настройка NVIDIA Container Toolkit (для GPU)

```bash
# Добавление репозитория NVIDIA
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

# Установка nvidia-container-toolkit
sudo apt update
sudo apt install -y nvidia-container-toolkit

# Перезапуск Docker
sudo systemctl restart docker
```

## 🚀 Быстрая установка

### 1. Клонирование репозитория

```bash
git clone https://github.com/DIZ-admin/erni-ki.git
cd erni-ki
```

### 2. Запуск скрипта установки

```bash
# Интерактивная установка
./scripts/setup/setup.sh

# Или быстрая установка с настройками по умолчанию
./scripts/setup/quick-start.sh
```

### 3. Проверка установки

```bash
# Проверка статуса всех сервисов
./scripts/maintenance/health-check.sh

# Проверка веб-интерфейсов
./scripts/maintenance/check-web-interfaces.sh
```

## 🔧 Ручная установка

### 1. Настройка переменных окружения

```bash
# Копирование примеров конфигураций (оптимизированная структура)
cp env/*.example env/
# Удалите расширение .example из скопированных файлов

# Редактирование основных настроек
nano env/db.env
nano env/ollama.env
nano env/openwebui.env
```

> **Примечание:** Структура конфигураций оптимизирована (август 2025). Все
> дублирующиеся конфигурации удалены, naming convention стандартизирован.

### 2. Настройка SSL сертификатов

```bash
# Генерация самоподписанных сертификатов (для тестирования)
./conf/ssl/generate-ssl-certs.sh

# Или размещение собственных сертификатов
cp your-cert.pem conf/ssl/cert.pem
cp your-key.pem conf/ssl/key.pem
```

### 3. Настройка Cloudflare Tunnel (опционально)

```bash
# Настройка cloudflared
nano env/cloudflared.env

# Добавление tunnel token
echo "TUNNEL_TOKEN=your_tunnel_token_here" >> env/cloudflared.env
```

### 4. Запуск системы

```bash
# Создание Docker сетей
./scripts/setup/create-networks.sh

# Запуск всех сервисов
docker compose up -d

# Проверка статуса
docker compose ps
```

## 🎯 Настройка GPU для Ollama

### 1. Проверка GPU

```bash
# Проверка доступности GPU
nvidia-smi

# Тест GPU в Docker
docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu20.04 nvidia-smi
```

### 2. Настройка Ollama для GPU

```bash
# Запуск скрипта настройки GPU
./scripts/setup/gpu-setup.sh

# Или ручная настройка
nano env/ollama.env
# Добавить: OLLAMA_GPU_ENABLED=true
```

### 3. Проверка GPU в Ollama

```bash
# Проверка использования GPU
./scripts/performance/gpu-performance-test.sh

# Мониторинг GPU
./scripts/performance/gpu-monitor.sh
```

## 📊 Настройка мониторинга

### 1. Развертывание системы мониторинга

```bash
# Автоматическая настройка
./scripts/setup/deploy-monitoring-system.sh

# Проверка статуса мониторинга
./scripts/performance/monitoring-system-status.sh

# Проверка webhook-receiver
curl -s http://localhost:9095/health
```

### 2. Доступ к интерфейсам мониторинга

- **Grafana:** <http://localhost:3000> (admin/admin)
- **Prometheus:** <http://localhost:9091>
- **AlertManager:** <http://localhost:9093>
- **Webhook Receiver:** <http://localhost:9095/health>
 - **Fluent Bit (Prometheus формат):** <http://localhost:2020/api/v1/metrics/prometheus>
 - **RAG Exporter:** <http://localhost:9808/metrics>

**Примечание:** Для внешнего доступа используйте домен ki.erni-gruppe.ch

### 3. Настройка GPU мониторинга

```bash
# Проверка NVIDIA GPU Exporter
curl -s http://localhost:9445/metrics | grep nvidia_gpu

# Проверка GPU дашборда в Grafana
# Откройте: http://localhost:3000/d/gpu-monitoring
```

## 🚀 Production оптимизации БД (Рекомендуется)

### 1. Оптимизация PostgreSQL

```bash
# Применение production конфигурации PostgreSQL
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "ALTER SYSTEM SET shared_buffers = '256MB';"
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "ALTER SYSTEM SET max_connections = 200;"
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "ALTER SYSTEM SET wal_buffers = '16MB';"
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "ALTER SYSTEM SET maintenance_work_mem = '64MB';"

# Настройка агрессивного автовакуума
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "ALTER SYSTEM SET autovacuum_max_workers = 4;"
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "ALTER SYSTEM SET autovacuum_naptime = '15s';"
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "ALTER SYSTEM SET autovacuum_vacuum_threshold = 25;"

# Включение логирования
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "ALTER SYSTEM SET log_connections = 'on';"
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "ALTER SYSTEM SET log_min_duration_statement = '100ms';"

## 🔎 Мониторинг RAG (SLA)

- В составе системы доступен сервис `rag-exporter` (порт 9808), публикующий метрики:
  - `erni_ki_rag_response_latency_seconds` (гистограмма латентности)
  - `erni_ki_rag_sources_count` (количество источников в ответе)
- Настройте `RAG_TEST_URL` в `compose.yml` для измерения реального RAG endpoint.
- В Grafana дашборд OpenWebUI содержит панели p95 < 2с и Sources Count.

## 🔁 Горячая перезагрузка Prometheus/Alertmanager

```bash
curl -X POST http://localhost:9091/-/reload  # Prometheus
curl -X POST http://localhost:9093/-/reload  # Alertmanager
```

# Перезапуск для применения изменений
docker-compose restart db
```

### 2. Оптимизация Redis

```bash
# Настройка memory limits
docker exec erni-ki-redis-1 redis-cli CONFIG SET maxmemory 2gb
docker exec erni-ki-redis-1 redis-cli CONFIG SET maxmemory-policy allkeys-lru

# Исправление memory overcommit warning
sudo sysctl vm.overcommit_memory=1
echo 'vm.overcommit_memory = 1' | sudo tee -a /etc/sysctl.conf
```

### 3. Верификация оптимизаций

```bash
# Проверка PostgreSQL настроек
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "SHOW shared_buffers;"
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "SHOW max_connections;"

# Проверка Redis настроек
docker exec erni-ki-redis-1 redis-cli CONFIG GET maxmemory
docker exec erni-ki-redis-1 redis-cli CONFIG GET maxmemory-policy

# Проверка производительности
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "
SELECT round(sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) * 100, 2) as cache_hit_ratio_percent
FROM pg_statio_user_tables;"
```

**Ожидаемые результаты:**

- PostgreSQL cache hit ratio: >95%
- Redis memory usage: <10% от лимита
- Время ответа БД: <100ms
- Отсутствие warning в логах

## 💾 Настройка backup

### 1. Настройка Backrest

```bash
# Автоматическая настройка
./scripts/setup/setup-backrest-integration.sh

# Проверка backup
./scripts/backup/check-local-backup.sh
```

### 2. Настройка расписания backup

```bash
# Настройка cron для автоматических backup
./scripts/setup/setup-cron-rotation.sh
```

## 🔒 Настройка безопасности

### 1. Усиление безопасности

```bash
# Применение security hardening
./scripts/security/security-hardening.sh

# Настройка мониторинга безопасности
./scripts/security/security-monitor.sh
```

### 2. Настройка firewall

```bash
# UFW (Ubuntu)
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable

# Firewalld (CentOS/RHEL)
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

## 🌐 Доступ к системе

### Основные интерфейсы

- **OpenWebUI:** <https://your-domain/> (основной интерфейс)
- **Grafana:** <https://your-domain/grafana> (мониторинг)
- **Kibana:** <https://your-domain/kibana> (логи)

### Первый вход

1. Откройте <https://your-domain/>
2. Создайте первого пользователя
3. Настройте модели в Ollama
4. Проверьте интеграции

## 🔧 Устранение проблем

### Общие проблемы

```bash
# Проверка логов
docker compose logs -f

# Перезапуск проблемных сервисов
docker compose restart service-name

# Полная диагностика
./scripts/troubleshooting/automated-recovery.sh
```

### Проблемы с GPU

```bash
# Диагностика GPU
./scripts/troubleshooting/test-healthcheck.sh

# Проверка драйверов NVIDIA
nvidia-smi
```

## 📞 Поддержка

- **📖 Документация:** [docs/troubleshooting.md](troubleshooting.md)
- **🐛 Issues:** [GitHub Issues](https://github.com/DIZ-admin/erni-ki/issues)
- **💬 Discussions:**
  [GitHub Discussions](https://github.com/DIZ-admin/erni-ki/discussions)

## 🆕 Важные обновления

### Август 2025 - Версия 5.0

**Исправления после установки:**

1. **SearXNG RAG интеграция** - если поиск не работает:

   ```bash
   # Проверить статус SearXNG
   docker logs erni-ki-searxng-1 --tail 20

   # При CAPTCHA ошибках от DuckDuckGo - уже исправлено в конфигурации
   # Активные движки: Startpage, Brave, Bing
   ```

2. **Backrest API** - использовать правильные endpoints:

   ```bash
   # Правильные JSON RPC endpoints
   curl -X POST 'http://localhost:9898/v1.Backrest/GetOperations' \
     --data '{}' -H 'Content-Type: application/json'
   ```

3. **Ollama модели** - доступны 6 моделей включая qwen2.5-coder:1.5b

---

**📝 Примечание:** Данное руководство актуализировано для архитектуры 20+
сервисов ERNI-KI версии 5.0.
