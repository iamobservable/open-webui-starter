# 🏗️ Архитектурная документация системы мониторинга ERNI-KI

> **Детальное описание архитектуры, компонентов и интеграций системы мониторинга AI-инфраструктуры**

## 📋 Содержание

1. [Общая архитектура](#общая-архитектура)
2. [Компоненты системы](#компоненты-системы)
3. [Сетевая архитектура](#сетевая-архитектура)
4. [Интеграция с Cloudflare](#интеграция-с-cloudflare)
5. [AI-мониторинг](#ai-мониторинг)
6. [Потоки данных](#потоки-данных)

## 🎯 Общая архитектура

### Архитектурная диаграмма системы мониторинга

```mermaid
graph TB
    subgraph "🌐 External Access"
        CF[Cloudflare Tunnels]
        EXT1[diz.zone]
        EXT2[search.diz.zone]
    end

    subgraph "📊 Monitoring Stack"
        PROM[Prometheus :9091]
        GRAF[Grafana :3000]
        ALERT[Alertmanager :9093]
        
        subgraph "🔍 Exporters"
            NODE[Node Exporter :9101]
            NVIDIA[NVIDIA Exporter :9445]
            POSTGRES[PostgreSQL Exporter :9187]
            REDIS[Redis Exporter :9121]
            OLLAMA[Ollama Exporter :9778]
            BLACKBOX[Blackbox Exporter :9115]
            CADVISOR[cAdvisor :8081]
        end
    end

    subgraph "📝 Logging Stack"
        ES[Elasticsearch :9200]
        KIBANA[Kibana :5601]
        FLUENT[Fluent Bit :2020/2021/24224]
    end

    subgraph "🤖 AI Services"
        OLLAMA_SVC[Ollama :11434]
        OPENWEBUI[OpenWebUI :8080]
        SEARXNG[SearXNG :8080]
    end

    subgraph "💾 Data Storage"
        POSTGRES_DB[(PostgreSQL)]
        REDIS_DB[(Redis)]
        ES_DATA[(Elasticsearch Data)]
    end

    %% Connections
    CF --> EXT1
    CF --> EXT2
    
    PROM --> NODE
    PROM --> NVIDIA
    PROM --> POSTGRES
    PROM --> REDIS
    PROM --> OLLAMA
    PROM --> BLACKBOX
    PROM --> CADVISOR
    
    GRAF --> PROM
    ALERT --> PROM
    
    OLLAMA --> OLLAMA_SVC
    BLACKBOX --> EXT1
    BLACKBOX --> EXT2
    
    FLUENT --> ES
    KIBANA --> ES
    
    POSTGRES --> POSTGRES_DB
    REDIS --> REDIS_DB
    ES --> ES_DATA

    %% Styling
    classDef monitoring fill:#e1f5fe
    classDef ai fill:#f3e5f5
    classDef storage fill:#e8f5e8
    classDef external fill:#fff3e0
    
    class PROM,GRAF,ALERT,NODE,NVIDIA,POSTGRES,REDIS,OLLAMA,BLACKBOX,CADVISOR monitoring
    class OLLAMA_SVC,OPENWEBUI,SEARXNG ai
    class POSTGRES_DB,REDIS_DB,ES_DATA storage
    class CF,EXT1,EXT2 external
```

## 🔧 Компоненты системы

### Основные сервисы мониторинга

| Компонент | Версия | Порт | Назначение | Статус |
|-----------|--------|------|------------|--------|
| **Prometheus** | 2.48.0 | 9091 | Сбор и хранение метрик | 🟢 |
| **Grafana** | 10.2.0 | 3000 | Визуализация данных | 🟢 |
| **Alertmanager** | 0.25.0 | 9093 | Управление алертами | 🟢 |
| **Elasticsearch** | 7.17.15 | 9200 | Хранение логов | 🟢 |
| **Kibana** | 7.17.15 | 5601 | Анализ логов | 🟢 |
| **Fluent Bit** | 2.1.10 | 2020/2021/24224 | Сбор логов | 🟢 |

### Exporters и мониторинг агенты

| Exporter | Версия | Порт | Мониторируемый сервис | Статус |
|----------|--------|------|-----------------------|--------|
| **Node Exporter** | 1.6.1 | 9101 | Системные ресурсы | 🟢 |
| **NVIDIA Exporter** | 1.2.0 | 9445 | GPU метрики | 🟢 |
| **PostgreSQL Exporter** | 0.13.2 | 9187 | База данных | 🟢 |
| **Redis Exporter** | 1.55.0 | 9121 | Кэш Redis | 🟢 |
| **Ollama Exporter** | Custom | 9778 | **AI-сервисы** | 🟢 |
| **Blackbox Exporter** | 0.24.0 | 9115 | HTTP/HTTPS проверки | 🟢 |
| **cAdvisor** | 0.47.2 | 8081 | Контейнеры | 🟢 |

## 🌐 Сетевая архитектура

### Сетевая диаграмма

```mermaid
graph LR
    subgraph "🌐 External Networks"
        INTERNET[Internet]
        CF_EDGE[Cloudflare Edge]
    end

    subgraph "🏠 Local Networks"
        subgraph "Frontend Network (172.20.0.0/24)"
            NGINX[Nginx :8080]
            OPENWEBUI[OpenWebUI :8080]
            SEARXNG[SearXNG :8080]
        end

        subgraph "Backend Network (172.21.0.0/24)"
            OLLAMA_SVC[Ollama :11434]
            POSTGRES_DB[PostgreSQL :5432]
            REDIS_DB[Redis :6379]
        end

        subgraph "Monitoring Network (172.22.0.0/24)"
            PROM[Prometheus :9091]
            GRAF[Grafana :3000]
            ES[Elasticsearch :9200]
            OLLAMA_EXP[Ollama Exporter :9778]
        end

        subgraph "Internal Network (172.23.0.0/24)"
            FLUENT[Fluent Bit]
            BLACKBOX[Blackbox Exporter]
        end

        subgraph "Host Network"
            OLLAMA_EXP_HOST[Ollama Exporter Host Mode]
        end
    end

    %% External connections
    INTERNET --> CF_EDGE
    CF_EDGE --> NGINX

    %% Internal connections
    PROM -.-> OLLAMA_EXP_HOST
    OLLAMA_EXP_HOST -.-> OLLAMA_SVC
    BLACKBOX --> INTERNET
    
    %% Network styling
    classDef frontend fill:#e3f2fd
    classDef backend fill:#f1f8e9
    classDef monitoring fill:#fce4ec
    classDef internal fill:#f3e5f5
    classDef host fill:#fff8e1
    
    class NGINX,OPENWEBUI,SEARXNG frontend
    class OLLAMA_SVC,POSTGRES_DB,REDIS_DB backend
    class PROM,GRAF,ES,OLLAMA_EXP monitoring
    class FLUENT,BLACKBOX internal
    class OLLAMA_EXP_HOST host
```

### Сетевые конфигурации

#### Основные сети Docker

```yaml
networks:
  # Основная сеть для внешнего доступа
  default:
    name: erni-ki-frontend
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24

  # Backend сеть для внутренних сервисов
  backend:
    name: erni-ki-backend
    driver: bridge
    ipam:
      config:
        - subnet: 172.21.0.0/24

  # Сеть мониторинга
  monitoring:
    name: erni-ki-monitoring
    driver: bridge
    ipam:
      config:
        - subnet: 172.22.0.0/24

  # Внутренняя сеть для высокопроизводительного взаимодействия
  internal:
    name: erni-ki-internal
    driver: bridge
    ipam:
      config:
        - subnet: 172.23.0.0/24
```

## ☁️ Интеграция с Cloudflare

### Архитектура Cloudflare туннелей

```mermaid
sequenceDiagram
    participant User as 👤 Пользователь
    participant CF as ☁️ Cloudflare Edge
    participant Tunnel as 🚇 Cloudflared Tunnel
    participant Nginx as 🌐 Nginx Proxy
    participant Services as 🔧 ERNI-KI Services

    User->>CF: HTTPS запрос к diz.zone
    CF->>Tunnel: Проксирование через туннель
    Tunnel->>Nginx: HTTP запрос к nginx:8080
    Nginx->>Services: Маршрутизация к сервисам
    Services-->>Nginx: Ответ сервиса
    Nginx-->>Tunnel: HTTP ответ
    Tunnel-->>CF: Ответ через туннель
    CF-->>User: HTTPS ответ с SSL
```

### Конфигурация доменов

| Домен | Статус | Назначение | Upstream |
|-------|--------|------------|----------|
| **diz.zone** | 🟢 Active | Основной интерфейс | nginx:8080 |
| **search.diz.zone** | 🟡 Issues | SearXNG поиск | searxng:8080 |
| **grafana.diz.zone** | ❌ Not configured | Мониторинг дашборды | grafana:3000 |

### HTTPS мониторинг

```mermaid
graph TD
    subgraph "🔍 Blackbox Exporter Monitoring"
        BB[Blackbox Exporter :9115]
        
        subgraph "📊 HTTPS Checks"
            CHECK1[https_2xx module]
            CHECK2[SSL Certificate validation]
            CHECK3[Response time measurement]
        end
    end

    subgraph "🌐 External Domains"
        DOMAIN1[diz.zone]
        DOMAIN2[search.diz.zone]
    end

    subgraph "📈 Prometheus"
        PROM[Prometheus :9091]
        TARGET1[blackbox-https job]
    end

    BB --> CHECK1
    BB --> CHECK2
    BB --> CHECK3
    
    CHECK1 --> DOMAIN1
    CHECK1 --> DOMAIN2
    
    PROM --> TARGET1
    TARGET1 --> BB

    %% Status indicators
    DOMAIN1 -.->|"✅ HTTP 200<br/>0.076s"| CHECK1
    DOMAIN2 -.->|"⚠️ HTTP 502<br/>0.085s"| CHECK1
```

## 🤖 AI-мониторинг

### Ollama Exporter архитектура

```mermaid
graph TB
    subgraph "🤖 AI Services"
        OLLAMA[Ollama Service :11434]
        
        subgraph "📊 Ollama API Endpoints"
            API1[/api/version]
            API2[/api/tags]
            API3[/api/ps]
        end
    end

    subgraph "📡 Ollama Exporter :9778"
        EXPORTER[Python Exporter]
        
        subgraph "🔄 Metrics Collection"
            COLLECTOR1[Version Collector]
            COLLECTOR2[Models Collector]
            COLLECTOR3[Process Collector]
        end
        
        subgraph "📈 Prometheus Metrics"
            METRIC1[ollama_info]
            METRIC2[ollama_models_total]
            METRIC3[ollama_model_size_bytes]
            METRIC4[ollama_running_models]
            METRIC5[ollama_up]
        end
    end

    subgraph "📊 Prometheus"
        PROM[Prometheus :9091]
        JOB[ollama-exporter job]
    end

    %% Connections
    EXPORTER --> API1
    EXPORTER --> API2
    EXPORTER --> API3
    
    COLLECTOR1 --> METRIC1
    COLLECTOR2 --> METRIC2
    COLLECTOR2 --> METRIC3
    COLLECTOR3 --> METRIC4
    EXPORTER --> METRIC5
    
    PROM --> JOB
    JOB --> EXPORTER

    %% Current data
    METRIC1 -.->|"version=0.11.3"| PROM
    METRIC2 -.->|"5 models"| PROM
    METRIC3 -.->|"30.66GB total"| PROM
    METRIC4 -.->|"0 running"| PROM
    METRIC5 -.->|"1 (UP)"| PROM
```

### AI-метрики детализация

#### Текущие модели в системе

```mermaid
pie title Распределение размеров моделей Ollama
    "gpt-oss:20b" : 13.78
    "gemma3n:e4b" : 7.55
    "deepseek-r1:7b" : 4.68
    "Mistral:7b" : 4.37
    "nomic-embed-text" : 0.27
```

## 📊 Потоки данных

### Поток метрик

```mermaid
flowchart TD
    subgraph "🎯 Targets"
        T1[System Metrics]
        T2[GPU Metrics]
        T3[Database Metrics]
        T4[AI Metrics]
        T5[HTTP Checks]
    end

    subgraph "📡 Exporters"
        E1[Node Exporter]
        E2[NVIDIA Exporter]
        E3[PostgreSQL Exporter]
        E4[Ollama Exporter]
        E5[Blackbox Exporter]
    end

    subgraph "📊 Collection"
        PROM[Prometheus]
        SCRAPE[Scraping :15s interval]
    end

    subgraph "📈 Visualization"
        GRAF[Grafana Dashboards]
        ALERT[Alertmanager]
    end

    subgraph "💾 Storage"
        TSDB[Time Series DB]
        RETENTION[30 days / 10GB]
    end

    T1 --> E1
    T2 --> E2
    T3 --> E3
    T4 --> E4
    T5 --> E5

    E1 --> SCRAPE
    E2 --> SCRAPE
    E3 --> SCRAPE
    E4 --> SCRAPE
    E5 --> SCRAPE

    SCRAPE --> PROM
    PROM --> TSDB
    TSDB --> RETENTION

    PROM --> GRAF
    PROM --> ALERT
```

### Поток логов

```mermaid
flowchart LR
    subgraph "📝 Log Sources"
        DOCKER[Docker Containers]
        SYSTEM[System Logs]
        APP[Application Logs]
    end

    subgraph "🔄 Collection"
        FLUENT[Fluent Bit]
        PARSE[Log Parsing]
        FILTER[Filtering]
    end

    subgraph "💾 Storage"
        ES[Elasticsearch]
        INDEX[Log Indexing]
    end

    subgraph "🔍 Analysis"
        KIBANA[Kibana]
        SEARCH[Log Search]
        VIZ[Visualization]
    end

    DOCKER --> FLUENT
    SYSTEM --> FLUENT
    APP --> FLUENT

    FLUENT --> PARSE
    PARSE --> FILTER
    FILTER --> ES

    ES --> INDEX
    INDEX --> KIBANA

    KIBANA --> SEARCH
    KIBANA --> VIZ
```

## 🔧 Конфигурационные особенности

### Elasticsearch Single-Node оптимизация

```yaml
# Ключевые настройки для single-node кластера
environment:
  - discovery.type=single-node          # Отключает кластерный режим
  - xpack.security.enabled=false        # Упрощает конфигурацию
  - "ES_JAVA_OPTS=-Xms2g -Xmx2g"       # Оптимизированный heap
  
# Шаблон для новых индексов без реплик
PUT _template/no_replicas
{
  "index_patterns": ["*"],
  "settings": {
    "number_of_replicas": 0             # Без реплик для single-node
  }
}
```

### Ollama Exporter конфигурация

```python
# Сетевая конфигурация для доступа к Ollama
network_mode: host                      # Использует host network
environment:
  - OLLAMA_URL=http://localhost:11434   # Прямой доступ к Ollama

# Метрики обновляются каждые 30 секунд
scrape_interval: 30s
metrics_path: /metrics
```

## 📋 Статус компонентов

### Текущее состояние системы

| Категория | Компонент | Статус | Примечания |
|-----------|-----------|--------|------------|
| **Core** | Prometheus | 🟢 | 23/37 targets UP |
| **Core** | Grafana | 🟢 | Все дашборды работают |
| **Core** | Alertmanager | 🟢 | 0 активных алертов |
| **Logs** | Elasticsearch | 🟢 | GREEN status, 0 unassigned shards |
| **Logs** | Kibana | 🟢 | Подключен к ES |
| **Logs** | Fluent Bit | 🟢 | Собирает логи |
| **AI** | Ollama Exporter | 🟢 | 5 моделей, 30.66GB |
| **Network** | Blackbox Exporter | 🟢 | HTTPS мониторинг активен |
| **External** | diz.zone | 🟢 | HTTP 200, 0.076s |
| **External** | search.diz.zone | 🟡 | HTTP 502, требует исправления |

---

*Архитектурная документация обновлена: 2025-08-07*  
*Версия системы мониторинга: 2.1.0*
