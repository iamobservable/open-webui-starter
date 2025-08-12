# ⚙️ Конфигурационное руководство системы мониторинга ERNI-KI

> **Детальное описание конфигураций, настроек и параметров всех компонентов системы мониторинга**

## 📋 Содержание

1. [Elasticsearch конфигурация](#elasticsearch-конфигурация)
2. [Ollama Exporter настройка](#ollama-exporter-настройка)
3. [Prometheus конфигурация](#prometheus-конфигурация)
4. [Отключенные targets](#отключенные-targets)
5. [Сетевые настройки](#сетевые-настройки)
6. [Переменные окружения](#переменные-окружения)

## 🗄️ Elasticsearch конфигурация

### Single-Node кластер оптимизация

#### Docker Compose настройки

```yaml
elasticsearch:
  image: docker.elastic.co/elasticsearch/elasticsearch:7.17.15
  container_name: erni-ki-elasticsearch
  
  # Конфигурация для single-node кластера
  environment:
    # Основные настройки single-node
    - discovery.type=single-node          # Отключает кластерный режим
    - xpack.security.enabled=false        # Упрощает безопасность
    - "ES_JAVA_OPTS=-Xms2g -Xmx2g"       # Heap memory 2GB
    
    # Дополнительные оптимизации
    - bootstrap.memory_lock=true          # Блокировка памяти
    - cluster.name=erni-ki-cluster        # Имя кластера
    - node.name=erni-ki-node-1           # Имя узла
    
  # Ресурсы контейнера
  deploy:
    resources:
      limits:
        memory: 3G                        # Увеличено с 2GB до 3GB
        cpus: "1.0"
      reservations:
        memory: 2G                        # Резерв памяти
        cpus: "0.5"
  
  # Настройки памяти
  ulimits:
    memlock:
      soft: -1                           # Неограниченная блокировка памяти
      hard: -1
    nofile:
      soft: 65536                        # Файловые дескрипторы
      hard: 65536
```

#### Шаблоны индексов без реплик

```bash
# Применение настроек для всех существующих индексов
curl -X PUT "localhost:9200/_all/_settings" -H 'Content-Type: application/json' -d'
{
  "index": {
    "number_of_replicas": 0              # Без реплик для single-node
  }
}'

# Шаблон для новых индексов
curl -X PUT "localhost:9200/_template/no_replicas" -H 'Content-Type: application/json' -d'
{
  "index_patterns": ["*"],
  "settings": {
    "number_of_replicas": 0,             # Без реплик по умолчанию
    "number_of_shards": 1                # Один шард для небольших данных
  }
}'
```

#### Результаты оптимизации

| Параметр | До оптимизации | После оптимизации |
|----------|----------------|-------------------|
| **Статус кластера** | 🟡 YELLOW | 🟢 GREEN |
| **Активные шарды** | 19 | 19 |
| **Неназначенные шарды** | 9 | 0 |
| **Процент активных шардов** | 67.86% | 100% |
| **Memory limit** | 2GB | 3GB |
| **Java heap** | 1GB | 2GB |

## 🤖 Ollama Exporter настройка

### Docker конфигурация

```yaml
ollama-exporter:
  build:
    context: .
    dockerfile: Dockerfile.ollama-exporter
  container_name: erni-ki-ollama-exporter
  
  # Сетевая конфигурация для доступа к Ollama
  network_mode: host                     # Использует host network для доступа к localhost:11434
  
  # Переменные окружения
  environment:
    - OLLAMA_URL=http://localhost:11434  # URL для подключения к Ollama
    - LOG_LEVEL=INFO                     # Уровень логирования
  
  # Ресурсы
  deploy:
    resources:
      limits:
        memory: 128M                     # Легковесный exporter
        cpus: "0.2"
      reservations:
        memory: 64M
        cpus: "0.1"
  
  # Health check
  healthcheck:
    test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:9778/metrics || exit 1"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 15s
```

### Python Exporter код

```python
class OllamaExporter:
    def __init__(self, ollama_url=None):
        # Получение URL из переменной окружения или использование по умолчанию
        self.ollama_url = ollama_url or os.getenv("OLLAMA_URL", "http://localhost:11434")
        
    def get_metrics(self):
        """Сбор метрик от Ollama API"""
        metrics = []
        
        try:
            # Версия Ollama
            version_resp = requests.get(f"{self.ollama_url}/api/version", timeout=5)
            if version_resp.status_code == 200:
                version_data = version_resp.json()
                metrics.append(f'ollama_info{{version="{version_data.get("version", "unknown")}"}} 1')
            
            # Список моделей и их размеры
            tags_resp = requests.get(f"{self.ollama_url}/api/tags", timeout=5)
            if tags_resp.status_code == 200:
                tags_data = tags_resp.json()
                models = tags_data.get("models", [])
                
                metrics.append(f'ollama_models_total {len(models)}')
                
                total_size = 0
                for model in models:
                    model_name = model.get("name", "unknown").replace(":", "_")
                    model_size = model.get("size", 0)
                    total_size += model_size
                    
                    metrics.append(f'ollama_model_size_bytes{{model="{model_name}"}} {model_size}')
                
                metrics.append(f'ollama_models_total_size_bytes {total_size}')
            
            # Запущенные процессы и VRAM
            ps_resp = requests.get(f"{self.ollama_url}/api/ps", timeout=5)
            if ps_resp.status_code == 200:
                ps_data = ps_resp.json()
                models = ps_data.get("models", [])
                metrics.append(f'ollama_running_models {len(models)}')
                
                for model in models:
                    model_name = model.get("name", "unknown").replace(":", "_")
                    size_vram = model.get("size_vram", 0)
                    metrics.append(f'ollama_model_vram_bytes{{model="{model_name}"}} {size_vram}')
            
            # Статус доступности
            metrics.append('ollama_up 1')
            
        except Exception as e:
            logger.error(f"Ошибка получения метрик: {e}")
            metrics.append('ollama_up 0')
        
        return "\n".join(metrics) + "\n"
```

### Текущие метрики

| Метрика | Значение | Описание |
|---------|----------|----------|
| `ollama_info{version="0.11.3"}` | 1 | Версия Ollama |
| `ollama_models_total` | 5 | Общее количество моделей |
| `ollama_models_total_size_bytes` | 30657965229 | Общий размер (30.66GB) |
| `ollama_running_models` | 0 | Запущенные модели |
| `ollama_up` | 1 | Статус доступности |

#### Детализация моделей

```
ollama_model_size_bytes{model="gpt-oss_20b"} 13780173839      # 13.78GB
ollama_model_size_bytes{model="Mistral_7b"} 4372824384        # 4.37GB  
ollama_model_size_bytes{model="gemma3n_e4b"} 7547589116       # 7.55GB
ollama_model_size_bytes{model="deepseek-r1_7b"} 4683075440    # 4.68GB
ollama_model_size_bytes{model="nomic-embed-text_latest"} 274302450  # 274MB
```

## 📊 Prometheus конфигурация

### Основные настройки

```yaml
global:
  scrape_interval: 15s                   # Интервал сбора метрик
  evaluation_interval: 15s               # Интервал оценки правил
  external_labels:
    cluster: 'erni-ki'                   # Метка кластера
    environment: 'production'            # Окружение

# Настройки хранения
storage:
  tsdb:
    retention.time: 30d                  # Хранение 30 дней
    retention.size: 10GB                 # Максимальный размер 10GB
```

### Job конфигурации

#### Ollama Exporter job

```yaml
# Ollama метрики - через custom exporter
- job_name: "ollama-exporter"
  static_configs:
    - targets: ["ollama-exporter:9778"]  # Подключение к exporter
  scrape_interval: 30s                   # Интервал сбора 30 секунд
  metrics_path: /metrics                 # Путь к метрикам
  scrape_timeout: 10s                    # Таймаут запроса
```

#### HTTPS мониторинг job

```yaml
# Blackbox exporter для проверки HTTPS доступности через Cloudflare
- job_name: "blackbox-https"
  metrics_path: /probe
  params:
    module: [https_2xx]                  # Модуль для HTTPS проверок
  static_configs:
    - targets:
        - https://diz.zone              # Основной домен
        - https://search.diz.zone       # Поддомен SearXNG
  relabel_configs:
    - source_labels: [__address__]
      target_label: __param_target
    - source_labels: [__param_target]
      target_label: instance
    - target_label: __address__
      replacement: blackbox-exporter:9115
```

## ❌ Отключенные targets

### Список отключенных targets с обоснованием

#### 1. Cloudflared metrics

```yaml
# Cloudflared метрики - ОТКЛЮЧЕНО (сервис не предоставляет /metrics endpoint)
# - job_name: "cloudflared"
#   static_configs:
#     - targets: ["cloudflared:8080"]
#   scrape_interval: 60s
#   metrics_path: /metrics
#   scrape_timeout: 15s
```

**Причина отключения**: Cloudflared является туннельным сервисом и не предоставляет Prometheus-совместимые метрики на порту 8080.

**Ошибка**: `dial tcp 172.20.0.5:8080: connect: connection refused`

#### 2. Elasticsearch direct metrics

```yaml
# Elasticsearch метрики - ОТКЛЮЧЕНО (требуется отдельный elasticsearch_exporter)
# - job_name: "elasticsearch"
#   static_configs:
#     - targets: ["elasticsearch:9200"]
#   scrape_interval: 30s
#   metrics_path: /_prometheus/metrics
#   scrape_timeout: 10s
```

**Причина отключения**: Elasticsearch не имеет встроенного Prometheus exporter. Требуется использование отдельного `elasticsearch_exporter`.

**Ошибка**: `server returned HTTP status 405 Method Not Allowed`

### Статистика targets

| Категория | До оптимизации | После оптимизации |
|-----------|----------------|-------------------|
| **Всего targets** | 39 | 37 |
| **UP targets** | 23 (59%) | 23 (62.2%) |
| **DOWN targets** | 16 (41%) | 14 (37.8%) |
| **Отключенные** | 0 | 2 |

## 🌐 Сетевые настройки

### Docker Networks конфигурация

```yaml
networks:
  # Основная сеть для внешнего доступа
  default:
    name: erni-ki-frontend
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: 172.20.0.0/24          # Frontend подсеть
          gateway: 172.20.0.1

  # Backend сеть для внутренних сервисов  
  backend:
    name: erni-ki-backend
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: 172.21.0.0/24          # Backend подсеть
          gateway: 172.21.0.1

  # Сеть мониторинга
  monitoring:
    name: erni-ki-monitoring
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: 172.22.0.0/24          # Monitoring подсеть
          gateway: 172.22.0.1

  # Внутренняя сеть для высокопроизводительного взаимодействия
  internal:
    name: erni-ki-internal
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: 172.23.0.0/24          # Internal подсеть
          gateway: 172.23.0.1
```

### IP адресация компонентов

| Компонент | Frontend | Backend | Monitoring | Internal |
|-----------|----------|---------|------------|----------|
| **Prometheus** | - | - | 172.22.0.1 | 172.23.0.1 |
| **Grafana** | 172.20.0.2 | - | 172.22.0.2 | - |
| **Elasticsearch** | - | - | 172.22.0.2 | - |
| **Ollama** | - | 172.21.0.3 | - | 172.23.0.3 |
| **Blackbox Exporter** | 172.20.0.92 | 172.21.0.92 | 172.22.0.92 | 172.23.0.92 |

### Особенности сетевой конфигурации

#### Ollama Exporter Host Network

```yaml
# Специальная конфигурация для доступа к Ollama
ollama-exporter:
  network_mode: host                     # Использует host network
  environment:
    - OLLAMA_URL=http://localhost:11434  # Прямой доступ через localhost
```

**Обоснование**: Ollama Exporter использует host network для прямого доступа к Ollama сервису, который работает на localhost:11434.

## 🔧 Переменные окружения

### Elasticsearch

```bash
# Основные настройки
discovery.type=single-node               # Режим single-node кластера
xpack.security.enabled=false             # Отключение X-Pack Security
ES_JAVA_OPTS=-Xms2g -Xmx2g              # Java heap memory 2GB

# Дополнительные настройки
bootstrap.memory_lock=true               # Блокировка памяти в RAM
cluster.name=erni-ki-cluster            # Имя кластера
node.name=erni-ki-node-1                # Имя узла
```

### Ollama Exporter

```bash
# Подключение к Ollama
OLLAMA_URL=http://localhost:11434        # URL Ollama API

# Настройки логирования
LOG_LEVEL=INFO                           # Уровень логирования
PYTHONUNBUFFERED=1                       # Небуферизованный вывод
```

### Prometheus

```bash
# Настройки хранения
PROMETHEUS_RETENTION_TIME=30d            # Время хранения метрик
PROMETHEUS_RETENTION_SIZE=10GB           # Размер хранения метрик

# Настройки производительности
PROMETHEUS_STORAGE_TSDB_MIN_BLOCK_DURATION=2h    # Минимальная длительность блока
PROMETHEUS_STORAGE_TSDB_MAX_BLOCK_DURATION=25h   # Максимальная длительность блока
```

### Fluent Bit

```bash
# Подключение к Elasticsearch
FLB_ES_HOST=elasticsearch                # Хост Elasticsearch
FLB_ES_PORT=9200                        # Порт Elasticsearch
FLB_ES_INDEX=erni-ki-logs               # Индекс для логов

# Настройки буферизации
FLB_BUFFER_CHUNK_SIZE=1MB               # Размер чанка буфера
FLB_BUFFER_MAX_SIZE=5MB                 # Максимальный размер буфера
```

## 📋 Проверка конфигураций

### Валидация Elasticsearch

```bash
# Проверка статуса кластера
curl -s http://localhost:9200/_cluster/health | jq '{status: .status, active_shards: .active_shards, unassigned_shards: .unassigned_shards}'

# Проверка настроек индексов
curl -s http://localhost:9200/_all/_settings | jq '.[] | .settings.index.number_of_replicas'

# Проверка шаблонов
curl -s http://localhost:9200/_template/no_replicas | jq '.no_replicas.settings'
```

### Валидация Ollama Exporter

```bash
# Проверка доступности метрик
curl -s http://localhost:9778/metrics | grep ollama_up

# Проверка подключения к Ollama
curl -s http://localhost:11434/api/version

# Проверка логов exporter
docker logs erni-ki-ollama-exporter --tail 10
```

### Валидация Prometheus targets

```bash
# Общая статистика targets
curl -s http://localhost:9091/api/v1/targets | jq '.data.activeTargets | length'

# UP targets
curl -s http://localhost:9091/api/v1/targets | jq '.data.activeTargets[] | select(.health == "up")' | jq -s 'length'

# Проверка конкретного job
curl -s http://localhost:9091/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job == "ollama-exporter")'
```

---

*Конфигурационная документация обновлена: 2025-08-07*  
*Версия системы мониторинга: 2.1.0*
