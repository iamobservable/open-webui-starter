# 📋 ERNI-KI: Подробная документация архитектуры проекта

## 📁 1. Структура проекта

```
erni-ki/
├── 📁 auth/                    # Микросервис JWT аутентификации (Go)
│   ├── Dockerfile             # Контейнер для auth сервиса
│   ├── go.mod, go.sum         # Go модули и зависимости
│   ├── main.go                # Основной код auth сервиса
│   └── main_test.go           # Тесты auth сервиса
├── 📁 cache/                   # Кэш директории для сервисов
│   └── backrest/              # Кэш для Backrest
├── 📁 conf/                    # Конфигурационные файлы сервисов
│   ├── backrest/              # Конфигурация Backrest
│   ├── cloudflare/            # Конфигурация Cloudflare туннелей
│   ├── litellm/               # Конфигурация LiteLLM прокси
│   ├── nginx/                 # Конфигурация Nginx (reverse proxy)
│   ├── openwebui/             # Конфигурация OpenWebUI
│   ├── searxng/               # Конфигурация SearXNG поисковика
│   └── watchtower/            # Конфигурация Watchtower
├── 📁 data/                    # Постоянные данные сервисов
│   ├── alertmanager/          # Данные AlertManager
│   ├── backrest/              # Репозитории резервных копий
│   ├── elasticsearch/         # Данные Elasticsearch
│   ├── grafana/               # Дашборды и настройки Grafana
│   ├── litellm/               # Данные LiteLLM
│   ├── ollama/                # Модели и данные Ollama
│   ├── openwebui/             # Пользовательские данные OpenWebUI
│   ├── postgres/              # База данных PostgreSQL
│   ├── prometheus/            # Метрики Prometheus
│   └── redis/                 # Данные Redis
├── 📁 docs/                    # Документация проекта
│   ├── de/                    # Немецкая локализация документации
│   ├── admin-guide.md         # Руководство администратора
│   ├── api-reference.md       # Справочник API
│   ├── architecture.md        # Архитектурная документация
│   └── installation-guide.md  # Руководство по установке
├── 📁 env/                     # Переменные окружения (.env файлы)
│   ├── auth.env               # Настройки auth сервиса
│   ├── backrest.env           # Настройки Backrest
│   ├── cloudflared.env        # Настройки Cloudflare туннелей
│   ├── db.env                 # Настройки PostgreSQL
│   ├── litellm.env            # Настройки LiteLLM
│   ├── ollama.env             # Настройки Ollama
│   ├── openwebui.env          # Настройки OpenWebUI
│   ├── redis.env              # Настройки Redis
│   └── searxng.env            # Настройки SearXNG
├── 📁 monitoring/              # Система мониторинга
│   ├── alertmanager/          # Конфигурация AlertManager
│   ├── blackbox/              # Конфигурация Blackbox Exporter
│   ├── elasticsearch/         # Конфигурация Elasticsearch
│   ├── fluent-bit/            # Конфигурация Fluent Bit
│   ├── grafana/               # Дашборды и настройки Grafana
│   ├── postgres-exporter/     # Конфигурация Postgres Exporter
│   ├── prometheus/            # Конфигурация Prometheus
│   ├── webhook-receiver/      # Webhook получатель для алертов
│   ├── docker-compose.monitoring.yml  # Docker Compose для мониторинга
│   ├── prometheus.yml         # Основная конфигурация Prometheus
│   └── alert_rules.yml        # Правила алертинга
├── 📁 scripts/                 # Скрипты автоматизации и управления
│   ├── setup.sh               # Скрипт первоначальной настройки
│   ├── quick_start.sh         # Быстрый запуск системы
│   ├── health_check.sh        # Проверка состояния сервисов
│   ├── backup-management.sh   # Управление резервными копиями
│   └── monitoring-deploy.sh   # Развертывание мониторинга
├── 📁 security/                # Политики безопасности
│   └── security-policy.md     # Политика безопасности проекта
├── 📁 tests/                   # Тесты системы
│   ├── global-setup.ts        # Глобальная настройка тестов
│   └── setup.ts               # Настройка тестовой среды
├── compose.yml                 # Основной Docker Compose файл
├── package.json               # Node.js зависимости для разработки
├── tsconfig.json              # Конфигурация TypeScript
├── vitest.config.ts           # Конфигурация тестового фреймворка
├── mkdocs.yml                 # Конфигурация документации MkDocs
└── README.md                  # Основная документация проекта
```

## 📊 2. Таблица сервисов

### Основные сервисы

| Сервис        | Описание                   | Docker образ                          | Порты         | Конфигурация        | Volumes                              | Зависимости                                                                      | Health Check                               | Ресурсы             |
| ------------- | -------------------------- | ------------------------------------- | ------------- | ------------------- | ------------------------------------ | -------------------------------------------------------------------------------- | ------------------------------------------ | ------------------- |
| **OpenWebUI** | Основной AI веб-интерфейс  | `ghcr.io/open-webui/open-webui:cuda`  | `8080:8080`   | `env/openwebui.env` | `./data/openwebui:/app/backend/data` | auth, docling, db, edgetts, mcposerver, nginx, ollama, searxng, tika, watchtower | `curl --fail http://localhost:8080/health` | GPU access          |
| **Ollama**    | Сервер языковых моделей    | `ollama/ollama:latest`                | `11434:11434` | `env/ollama.env`    | `./data/ollama:/root/.ollama`        | watchtower                                                                       | `ollama list`                              | GPU access, 4GB RAM |
| **LiteLLM**   | Прокси для LLM провайдеров | `ghcr.io/berriai/litellm:main-latest` | `4000:4000`   | `env/litellm.env`   | `./data/litellm:/app/data`           | db, redis, watchtower                                                            | `curl --fail http://localhost:4000/health` | 1GB RAM             |

### Базы данных

| Сервис            | Описание                        | Docker образ                                            | Порты       | Конфигурация      | Volumes                                               | Зависимости | Health Check                                    | Ресурсы   |
| ----------------- | ------------------------------- | ------------------------------------------------------- | ----------- | ----------------- | ----------------------------------------------------- | ----------- | ----------------------------------------------- | --------- |
| **PostgreSQL**    | Основная база данных с pgvector | `pgvector/pgvector:pg16`                                | `5432:5432` | `env/db.env`      | `./data/postgres:/var/lib/postgresql/data`            | watchtower  | `pg_isready -d $POSTGRES_DB -U $POSTGRES_USER`  | 2GB RAM   |
| **Redis**         | Кэш и очереди                   | `redis/redis-stack:latest`                              | `6379:6379` | `env/redis.env`   | `./data/redis:/data`                                  | watchtower  | `redis-cli ping \| grep PONG`                   | 512MB RAM |
| **Elasticsearch** | Поисковая база для логов        | `docker.elastic.co/elasticsearch/elasticsearch:7.17.15` | `9200:9200` | monitoring config | `../data/elasticsearch:/usr/share/elasticsearch/data` | -           | `curl -f http://localhost:9200/_cluster/health` | 2GB RAM   |

### Мониторинг

| Сервис                | Описание                  | Docker образ                                    | Порты       | Конфигурация                  | Volumes                                    | Зависимости   | Health Check                                    | Ресурсы   |
| --------------------- | ------------------------- | ----------------------------------------------- | ----------- | ----------------------------- | ------------------------------------------ | ------------- | ----------------------------------------------- | --------- |
| **Prometheus**        | Сбор и хранение метрик    | `prom/prometheus:v2.45.0`                       | `9091:9090` | `monitoring/prometheus.yml`   | `../data/prometheus:/prometheus`           | -             | `wget --spider http://localhost:9090/-/healthy` | 1GB RAM   |
| **Grafana**           | Визуализация метрик       | `grafana/grafana:10.0.3`                        | `3000:3000` | monitoring config             | `../data/grafana:/var/lib/grafana`         | prometheus    | `curl -f http://localhost:3000/api/health`      | 512MB RAM |
| **AlertManager**      | Управление алертами       | `prom/alertmanager:v0.25.0`                     | `9093:9093` | `monitoring/alertmanager.yml` | `../data/alertmanager:/alertmanager`       | -             | `wget --spider http://localhost:9093/-/healthy` | 256MB RAM |
| **Node Exporter**     | Системные метрики хоста   | `prom/node-exporter:v1.6.1`                     | `9101:9100` | -                             | `/proc:/host/proc:ro`, `/sys:/host/sys:ro` | -             | `curl -f http://localhost:9100/metrics`         | 64MB RAM  |
| **cAdvisor**          | Метрики контейнеров       | `gcr.io/cadvisor/cadvisor:v0.47.2`              | `8081:8080` | optimized command             | `/:/rootfs:ro`, `/var/run:/var/run:ro`     | -             | `wget --spider http://localhost:8080/healthz`   | 256MB RAM |
| **Postgres Exporter** | Метрики PostgreSQL        | `prometheuscommunity/postgres-exporter:v0.15.0` | `9187:9187` | monitoring config             | queries config                             | db            | `curl -f http://localhost:9187/metrics`         | 64MB RAM  |
| **Redis Exporter**    | Метрики Redis             | `oliver006/redis_exporter:v1.53.0`              | `9121:9121` | -                             | -                                          | redis         | `curl -f http://localhost:9121/metrics`         | 32MB RAM  |
| **Nvidia Exporter**   | Метрики GPU               | `mindprince/nvidia_gpu_prometheus_exporter:0.1` | `9445:9445` | GPU runtime                   | -                                          | -             | `pgrep -f nvidia_gpu_prometheus_exporter`       | 64MB RAM  |
| **Blackbox Exporter** | Проверка доступности      | `prom/blackbox-exporter:v0.24.0`                | `9115:9115` | monitoring config             | -                                          | -             | `curl -f http://localhost:9115/metrics`         | 32MB RAM  |
| **Fluent Bit**        | Сбор и отправка логов     | `fluent/fluent-bit:3.0.7`                       | `2020:2020` | `monitoring/fluent-bit/`      | `/var/log:/var/log:ro`                     | elasticsearch | Health check отключен                           | 256MB RAM |
| **Kibana**            | Визуализация логов        | `docker.elastic.co/kibana/kibana:7.17.15`       | `5601:5601` | monitoring config             | -                                          | elasticsearch | `curl -f http://localhost:5601/api/status`      | 1GB RAM   |
| **Webhook Receiver**  | Получение webhook алертов | `adnanh/webhook:2.8.0`                          | `9000:9000` | monitoring config             | -                                          | -             | `curl -f http://localhost:9000/hooks/health`    | 32MB RAM  |

### Инфраструктура

| Сервис           | Описание                      | Docker образ                    | Порты                           | Конфигурация          | Volumes                    | Зависимости              | Health Check                         | Ресурсы   |
| ---------------- | ----------------------------- | ------------------------------- | ------------------------------- | --------------------- | -------------------------- | ------------------------ | ------------------------------------ | --------- |
| **Nginx**        | Reverse proxy и балансировщик | `nginx:alpine`                  | `80:80`, `443:443`, `8080:8080` | `conf/nginx/`         | nginx configs              | auth, openwebui, searxng | `curl -f http://localhost:80/health` | 128MB RAM |
| **Auth Service** | JWT аутентификация            | `custom build`                  | `9090:9090`                     | `env/auth.env`        | -                          | watchtower               | `/app/main --health-check`           | 64MB RAM  |
| **Cloudflared**  | Cloudflare туннель            | `cloudflare/cloudflared:latest` | -                               | `env/cloudflared.env` | `./conf/cloudflare/config` | watchtower               | `cloudflared tunnel info`            | 64MB RAM  |
| **Watchtower**   | Автообновление контейнеров    | `containrrr/watchtower:latest`  | -                               | `env/watchtower.env`  | `/var/run/docker.sock:ro`  | -                        | `/watchtower --health-check`         | 128MB RAM |

### Утилиты и дополнительные сервисы

| Сервис         | Описание                        | Docker образ                      | Порты       | Конфигурация         | Volumes                 | Зависимости           | Health Check                                | Ресурсы   |
| -------------- | ------------------------------- | --------------------------------- | ----------- | -------------------- | ----------------------- | --------------------- | ------------------------------------------- | --------- |
| **SearXNG**    | Метапоисковый движок            | `searxng/searxng:latest`          | `8080:8080` | `conf/searxng/`      | searxng configs         | watchtower            | `curl -f http://localhost:8080/healthz`     | 256MB RAM |
| **Backrest**   | Система резервного копирования  | `garethgeorge/backrest:latest`    | `9898:9898` | `env/backrest.env`   | backup sources, configs | db, redis, watchtower | `curl --fail http://localhost:9898/health`  | 256MB RAM |
| **Tika**       | Извлечение текста из документов | `apache/tika:latest`              | `9998:9998` | `env/tika.env`       | -                       | watchtower            | `curl --fail http://localhost:9998/version` | 512MB RAM |
| **Docling**    | Обработка документов с OCR      | `ds4sd/docling:latest`            | `5000:5000` | `env/docling.env`    | -                       | watchtower            | `curl --fail http://localhost:5000/health`  | 1GB RAM   |
| **EdgeTTS**    | Синтез речи                     | `travisvn/openai-edge-tts:latest` | `5050:5050` | `env/edgetts.env`    | -                       | watchtower            | `curl --fail http://localhost:5050/voices`  | 128MB RAM |
| **MCP Server** | Context Engineering сервер      | `ghcr.io/open-webui/mcpo:latest`  | -           | `env/mcposerver.env` | `./conf/mcposerver`     | watchtower            | `ps aux \| grep mcpo`                       | 128MB RAM |

## 🏗️ 3. Группировка по категориям

### 🎯 Основные сервисы (Core Services)

- **OpenWebUI**: Главный пользовательский интерфейс для AI взаимодействий
- **Ollama**: Локальный сервер языковых моделей с GPU поддержкой
- **LiteLLM**: Прокси для интеграции с внешними LLM провайдерами

### 🗄️ Базы данных (Database Services)

- **PostgreSQL**: Основная реляционная БД с векторным расширением pgvector
- **Redis**: In-memory кэш и брокер сообщений
- **Elasticsearch**: Поисковая база данных для логов и аналитики

### 📊 Мониторинг (Monitoring Services)

- **Prometheus**: Сбор и хранение временных рядов метрик
- **Grafana**: Визуализация метрик и создание дашбордов
- **AlertManager**: Управление и маршрутизация алертов
- **Экспортеры**: Node, cAdvisor, Postgres, Redis, Nvidia, Blackbox
- **Fluent Bit**: Сбор и агрегация логов
- **Kibana**: Анализ и визуализация логов
- **Elasticsearch**: Хранение логов

### 🌐 Инфраструктура (Infrastructure Services)

- **Nginx**: Reverse proxy, SSL termination, load balancing
- **Auth Service**: Централизованная JWT аутентификация
- **Cloudflared**: Безопасные туннели через Cloudflare
- **Watchtower**: Автоматическое обновление Docker контейнеров

### 🔧 Утилиты (Utility Services)

- **SearXNG**: Приватный метапоисковый движок для RAG
- **Backrest**: Автоматизированное резервное копирование
- **Tika**: Извлечение метаданных и текста из документов
- **Docling**: OCR и обработка документов с поддержкой множества языков
- **EdgeTTS**: Синтез речи для голосовых функций
- **MCP Server**: Context Engineering для расширенных AI возможностей

## 🌐 4. Сетевая архитектура

### Docker Networks

```yaml
networks:
  default:
    name: erni-ki_default
    driver: bridge
  monitoring:
    name: erni-ki_monitoring
    driver: bridge
```

### Внутренние соединения

```text
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│     Nginx       │────│   OpenWebUI     │────│     Ollama      │
│   (Port 80/443) │    │   (Port 8080)   │    │  (Port 11434)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │              ┌─────────────────┐              │
         │              │   PostgreSQL    │              │
         │              │   (Port 5432)   │              │
         │              └─────────────────┘              │
         │                       │                       │
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│    SearXNG      │────│      Redis      │────│    LiteLLM      │
│   (Port 8080)   │    │   (Port 6379)   │    │   (Port 4000)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Внешние подключения

- **HTTP/HTTPS**: Nginx (80/443) → Cloudflare → Internet
- **Cloudflare Tunnel**: Cloudflared → Cloudflare Edge
- **Monitoring**: Grafana (3000), Prometheus (9091) через Nginx proxy
- **Admin Interfaces**: Backrest (9898), Auth (9090)

### Потоки данных

```text
Internet → Cloudflare → Nginx → OpenWebUI → Ollama (AI модели)
                    ↓              ↓
                SearXNG ←→ PostgreSQL (векторная БД)
                    ↓              ↓
                 Redis ←→ LiteLLM (внешние LLM)
```

## 📋 5. Детальные конфигурации

### 🔧 Переменные окружения

#### OpenWebUI (`env/openwebui.env`)

```bash
# Основные настройки
WEBUI_NAME=ERNI-KI
WEBUI_URL=https://your-domain.com
WEBUI_SECRET_KEY=your-secret-key

# Интеграции
OLLAMA_BASE_URL=http://ollama:11434
OPENAI_API_BASE_URL=http://litellm:4000/v1
ENABLE_RAG_WEB_SEARCH=true
RAG_WEB_SEARCH_ENGINE=searxng
SEARXNG_QUERY_URL=http://searxng:8080/search?q=<query>

# База данных
DATABASE_URL=postgresql://postgres:password@db:5432/openwebui

# Аутентификация
ENABLE_OAUTH_SIGNUP=true
OAUTH_MERGE_ACCOUNTS_BY_EMAIL=true
```

#### Ollama (`env/ollama.env`)

```bash
# GPU настройки
NVIDIA_VISIBLE_DEVICES=all
OLLAMA_GPU_LAYERS=35
OLLAMA_NUM_PARALLEL=4
OLLAMA_MAX_LOADED_MODELS=2

# Производительность
OLLAMA_FLASH_ATTENTION=1
OLLAMA_HOST=0.0.0.0:11434
OLLAMA_ORIGINS=*
```

#### LiteLLM (`env/litellm.env`)

```bash
# Основные настройки
LITELLM_MASTER_KEY=sk-your-master-key
LITELLM_SALT_KEY=your-salt-key
DATABASE_URL=postgresql://postgres:password@db:5432/openwebui

# Интеграции
OLLAMA_API_BASE=http://ollama:11434
REDIS_HOST=redis
REDIS_PORT=6379

# Безопасность
MAX_BUDGET=1000
ENABLE_AUDIT_LOGS=true
DISABLE_SPEND_LOGS=true
```

### 🗄️ Конфигурации сервисов

#### Nginx (`conf/nginx/default.conf`)

```nginx
# Основной сервер блок
server {
    listen 80;
    listen 443 ssl http2;
    server_name _;

    # SSL конфигурация
    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;

    # Проксирование к OpenWebUI
    location / {
        proxy_pass http://openwebui:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Проксирование к SearXNG
    location /search {
        proxy_pass http://searxng:8080;
        proxy_set_header Host searxng.local;
    }
}
```

#### Prometheus (`monitoring/prometheus.yml`)

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - 'alert_rules.yml'

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  - job_name: 'postgres-exporter'
    static_configs:
      - targets: ['postgres-exporter:9187']

  - job_name: 'redis-exporter'
    static_configs:
      - targets: ['redis-exporter:9121']

  - job_name: 'nvidia-exporter'
    static_configs:
      - targets: ['nvidia-exporter:9445']
```

## 🔒 6. Безопасность и доступ

### Аутентификация

- **JWT токены**: Централизованная аутентификация через Auth Service
- **OAuth интеграция**: Поддержка внешних провайдеров
- **Session management**: Redis для хранения сессий

### Сетевая безопасность

- **Reverse proxy**: Nginx как единая точка входа
- **SSL/TLS**: Автоматические сертификаты через Cloudflare
- **Rate limiting**: Настроенные лимиты в Nginx
- **Firewall**: Только необходимые порты открыты

### Мониторинг безопасности

- **Audit logs**: Логирование всех действий пользователей
- **Security alerts**: Алерты на подозрительную активность
- **Access logs**: Детальное логирование доступа

## 📊 7. Производительность и масштабирование

### Ресурсные требования

- **Минимум**: 8GB RAM, 4 CPU cores, 100GB storage
- **Рекомендуемо**: 16GB RAM, 8 CPU cores, 500GB SSD, GPU
- **Production**: 32GB RAM, 16 CPU cores, 1TB NVMe, RTX 4090

### Оптимизации

- **GPU ускорение**: Ollama с CUDA поддержкой
- **Кэширование**: Redis для быстрого доступа к данным
- **Векторный поиск**: pgvector для эффективного RAG
- **Мониторинг производительности**: Детальные метрики всех компонентов

### Масштабирование

- **Горизонтальное**: Возможность запуска нескольких экземпляров
- **Load balancing**: Nginx для распределения нагрузки
- **Database scaling**: PostgreSQL с возможностью репликации
- **Monitoring scaling**: Prometheus federation для больших установок

## 🚀 8. Развертывание и управление

### Порядок запуска сервисов

```bash
# 1. Базовые сервисы
docker compose up -d watchtower db redis

# 2. Вспомогательные сервисы
docker compose up -d auth searxng nginx

# 3. AI сервисы
docker compose up -d ollama litellm

# 4. Основной интерфейс
docker compose up -d openwebui

# 5. Мониторинг (опционально)
cd monitoring && docker compose -f docker-compose.monitoring.yml up -d
```

### Команды управления

```bash
# Проверка статуса всех сервисов
docker compose ps

# Просмотр логов конкретного сервиса
docker compose logs -f openwebui

# Перезапуск сервиса
docker compose restart ollama

# Обновление сервисов
docker compose pull && docker compose up -d

# Остановка всех сервисов
docker compose down
```

### Резервное копирование

```bash
# Создание резервной копии
docker exec erni-ki-backrest-1 backrest backup --tag "manual-$(date +%Y%m%d)"

# Восстановление из резервной копии
docker exec erni-ki-backrest-1 backrest restore --snapshot latest

# Проверка статуса резервных копий
curl http://localhost:9898/api/v1/repos
```

## 🔧 9. Обслуживание и мониторинг

### Ключевые метрики для мониторинга

- **Системные**: CPU, RAM, Disk I/O, Network
- **Контейнеры**: Статус, ресурсы, health checks
- **Базы данных**: Подключения, запросы, размер БД
- **AI сервисы**: Время отклика, использование GPU, загруженные модели
- **Сеть**: Latency, throughput, ошибки подключения

### Алерты и уведомления

- **Критические**: Недоступность сервисов, переполнение диска
- **Предупреждения**: Высокая нагрузка, медленные запросы
- **Информационные**: Обновления, успешные резервные копии

### Регулярное обслуживание

- **Ежедневно**: Проверка логов, мониторинг ресурсов
- **Еженедельно**: Очистка старых логов, проверка резервных копий
- **Ежемесячно**: Обновление сервисов, анализ производительности
- **Ежеквартально**: Аудит безопасности, планирование масштабирования

## 📚 10. Справочная информация

### Полезные команды Docker

```bash
# Просмотр использования ресурсов
docker stats

# Очистка неиспользуемых ресурсов
docker system prune -f

# Просмотр сетей Docker
docker network ls

# Инспекция конкретного контейнера
docker inspect erni-ki-openwebui-1
```

### Порты и эндпоинты

| Сервис     | Порт  | Эндпоинт    | Описание                      |
| ---------- | ----- | ----------- | ----------------------------- |
| OpenWebUI  | 8080  | `/`         | Основной интерфейс            |
| Ollama     | 11434 | `/api/tags` | API языковых моделей          |
| LiteLLM    | 4000  | `/health`   | Прокси для LLM                |
| Grafana    | 3000  | `/`         | Дашборды мониторинга          |
| Prometheus | 9091  | `/`         | Метрики системы               |
| Backrest   | 9898  | `/`         | Управление резервными копиями |
| Auth       | 9090  | `/health`   | Аутентификация                |

### Файлы конфигурации

- **Docker Compose**: `compose.yml`, `monitoring/docker-compose.monitoring.yml`
- **Переменные окружения**: `env/*.env`
- **Конфигурации сервисов**: `conf/*/`
- **Мониторинг**: `monitoring/prometheus.yml`, `monitoring/alert_rules.yml`
- **Nginx**: `conf/nginx/default.conf`
- **Документация**: `docs/*.md`

### Логи и данные

- **Логи приложений**: `docker compose logs [service]`
- **Системные логи**: `/var/log/` (через Fluent Bit)
- **Данные сервисов**: `data/*/`
- **Резервные копии**: `data/backrest/repositories/`
- **Конфигурации**: `conf/*/`

---

**Документация создана:** $(date) **Версия ERNI-KI:** Latest **Автор:** Augment
Code AI Assistant

> 💡 **Совет**: Регулярно обновляйте эту документацию при изменении архитектуры
> системы или добавлении новых сервисов.
