# 🔧 Руководство по эксплуатации системы мониторинга ERNI-KI

> **Практическое руководство по управлению, диагностике и обслуживанию системы мониторинга AI-инфраструктуры**

## 📋 Содержание

1. [Мониторинг AI-сервисов](#мониторинг-ai-сервисов)
2. [Диагностика недоступных targets](#диагностика-недоступных-targets)
3. [HTTPS мониторинг внешних доменов](#https-мониторинг-внешних-доменов)
4. [Управление Elasticsearch](#управление-elasticsearch)
5. [Процедуры обслуживания](#процедуры-обслуживания)
6. [Устранение неисправностей](#устранение-неисправностей)

## 🤖 Мониторинг AI-сервисов

### Ollama Exporter управление

#### Запуск и остановка

```bash
# Запуск Ollama Exporter
docker run -d --name erni-ki-ollama-exporter \
  --network host \
  -e OLLAMA_URL=http://localhost:11434 \
  erni-ki-ollama-exporter:latest

# Остановка и удаление
docker stop erni-ki-ollama-exporter
docker rm erni-ki-ollama-exporter

# Перезапуск с новой конфигурацией
docker-compose -f monitoring/docker-compose.monitoring.yml restart ollama-exporter
```

#### Проверка статуса AI-сервисов

```bash
# 1. Проверка доступности Ollama Exporter
curl -s http://localhost:9778/metrics | grep ollama_up
# Ожидаемый результат: ollama_up 1

# 2. Проверка версии Ollama
curl -s http://localhost:9778/metrics | grep ollama_info
# Ожидаемый результат: ollama_info{version="0.11.3"} 1

# 3. Проверка количества моделей
curl -s http://localhost:9778/metrics | grep ollama_models_total
# Ожидаемый результат: ollama_models_total 5

# 4. Проверка общего размера моделей
curl -s http://localhost:9778/metrics | grep ollama_models_total_size_bytes
# Ожидаемый результат: ollama_models_total_size_bytes 30657965229

# 5. Проверка запущенных моделей
curl -s http://localhost:9778/metrics | grep ollama_running_models
# Ожидаемый результат: ollama_running_models 0
```

#### Мониторинг производительности AI

```bash
# Скрипт для мониторинга AI-метрик
cat > monitor_ai.sh << 'EOF'
#!/bin/bash

echo "=== AI-СЕРВИСЫ МОНИТОРИНГ ==="
echo "Время: $(date)"
echo ""

# Статус Ollama
OLLAMA_UP=$(curl -s http://localhost:9778/metrics | grep "ollama_up" | awk '{print $2}')
if [ "$OLLAMA_UP" = "1" ]; then
    echo "✅ Ollama: ДОСТУПЕН"
else
    echo "❌ Ollama: НЕДОСТУПЕН"
fi

# Версия Ollama
VERSION=$(curl -s http://localhost:11434/api/version | jq -r '.version')
echo "📦 Версия Ollama: $VERSION"

# Количество моделей
MODELS_COUNT=$(curl -s http://localhost:9778/metrics | grep "ollama_models_total" | head -1 | awk '{print $2}')
echo "🧠 Всего моделей: $MODELS_COUNT"

# Общий размер моделей в GB
TOTAL_SIZE_BYTES=$(curl -s http://localhost:9778/metrics | grep "ollama_models_total_size_bytes" | awk '{print $2}')
TOTAL_SIZE_GB=$(echo "scale=2; $TOTAL_SIZE_BYTES / 1024 / 1024 / 1024" | bc)
echo "💾 Общий размер: ${TOTAL_SIZE_GB}GB"

# Запущенные модели
RUNNING_MODELS=$(curl -s http://localhost:9778/metrics | grep "ollama_running_models" | awk '{print $2}')
echo "🏃 Запущенные модели: $RUNNING_MODELS"

# GPU использование (если доступно)
if command -v nvidia-smi &> /dev/null; then
    echo ""
    echo "🎮 GPU статус:"
    nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits | \
    while IFS=, read name mem_used mem_total util; do
        echo "   $name: ${mem_used}MB/${mem_total}MB (${util}%)"
    done
fi

echo ""
echo "=== КОНЕЦ ОТЧЕТА ==="
EOF

chmod +x monitor_ai.sh
./monitor_ai.sh
```

#### Алерты для AI-сервисов

```yaml
# Добавить в monitoring/alert_rules.yml
groups:
  - name: ai_services
    rules:
      # Ollama недоступен
      - alert: OllamaDown
        expr: ollama_up == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Ollama сервис недоступен"
          description: "Ollama не отвечает более 2 минут"

      # Слишком много запущенных моделей
      - alert: TooManyRunningModels
        expr: ollama_running_models > 2
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Много запущенных AI-моделей"
          description: "Запущено {{ $value }} моделей, возможна нехватка VRAM"

      # Большой размер моделей
      - alert: LargeModelsSize
        expr: ollama_models_total_size_bytes > 50000000000  # 50GB
        for: 1m
        labels:
          severity: info
        annotations:
          summary: "Большой размер AI-моделей"
          description: "Общий размер моделей: {{ $value | humanize }}B"
```

## 🎯 Диагностика недоступных targets

### Систематическая диагностика

#### Скрипт диагностики targets

```bash
# Создание скрипта диагностики
cat > diagnose_targets.sh << 'EOF'
#!/bin/bash

echo "=== ДИАГНОСТИКА PROMETHEUS TARGETS ==="
echo "Время: $(date)"
echo ""

# Общая статистика
TOTAL_TARGETS=$(curl -s http://localhost:9091/api/v1/targets | jq '.data.activeTargets | length')
UP_TARGETS=$(curl -s http://localhost:9091/api/v1/targets | jq '.data.activeTargets[] | select(.health == "up")' | jq -s 'length')
DOWN_TARGETS=$((TOTAL_TARGETS - UP_TARGETS))

echo "📊 Общая статистика:"
echo "   Всего targets: $TOTAL_TARGETS"
echo "   UP targets: $UP_TARGETS ($(echo "scale=1; $UP_TARGETS * 100 / $TOTAL_TARGETS" | bc)%)"
echo "   DOWN targets: $DOWN_TARGETS ($(echo "scale=1; $DOWN_TARGETS * 100 / $TOTAL_TARGETS" | bc)%)"
echo ""

# Анализ DOWN targets
echo "❌ Недоступные targets:"
curl -s http://localhost:9091/api/v1/targets | jq -r '.data.activeTargets[] | select(.health == "down") | "   \(.labels.job):\(.labels.instance) - \(.lastError)"'

echo ""
echo "✅ Доступные targets:"
curl -s http://localhost:9091/api/v1/targets | jq -r '.data.activeTargets[] | select(.health == "up") | "   \(.labels.job):\(.labels.instance)"'

echo ""
echo "=== РЕКОМЕНДАЦИИ ПО ИСПРАВЛЕНИЮ ==="

# Проверка DNS резолюции
echo "🔍 Проверка DNS резолюции:"
for target in $(curl -s http://localhost:9091/api/v1/targets | jq -r '.data.activeTargets[] | select(.health == "down") | .labels.instance' | cut -d: -f1 | sort -u); do
    if [[ "$target" != "localhost" && "$target" != "127.0.0.1" ]]; then
        if nslookup "$target" > /dev/null 2>&1; then
            echo "   ✅ $target: DNS OK"
        else
            echo "   ❌ $target: DNS FAILED"
        fi
    fi
done

echo ""
echo "🌐 Проверка сетевой доступности:"
for target in $(curl -s http://localhost:9091/api/v1/targets | jq -r '.data.activeTargets[] | select(.health == "down") | .labels.instance'); do
    host=$(echo $target | cut -d: -f1)
    port=$(echo $target | cut -d: -f2)
    
    if timeout 3 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
        echo "   ✅ $target: Порт доступен"
    else
        echo "   ❌ $target: Порт недоступен"
    fi
done

echo ""
echo "=== КОНЕЦ ДИАГНОСТИКИ ==="
EOF

chmod +x diagnose_targets.sh
./diagnose_targets.sh
```

#### Пошаговая диагностика проблемного target

```bash
# Функция для диагностики конкретного target
diagnose_target() {
    local job=$1
    local instance=$2
    
    echo "=== ДИАГНОСТИКА TARGET: $job:$instance ==="
    
    # 1. Проверка статуса в Prometheus
    echo "1. Статус в Prometheus:"
    curl -s http://localhost:9091/api/v1/targets | jq ".data.activeTargets[] | select(.labels.job == \"$job\" and .labels.instance == \"$instance\")"
    
    # 2. Проверка DNS
    host=$(echo $instance | cut -d: -f1)
    port=$(echo $instance | cut -d: -f2)
    
    echo ""
    echo "2. DNS резолюция:"
    nslookup $host || echo "DNS резолюция не удалась"
    
    # 3. Проверка сетевой доступности
    echo ""
    echo "3. Сетевая доступность:"
    if timeout 5 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
        echo "✅ Порт $port на $host доступен"
    else
        echo "❌ Порт $port на $host недоступен"
    fi
    
    # 4. Проверка HTTP endpoint
    echo ""
    echo "4. HTTP endpoint:"
    curl -s -o /dev/null -w "HTTP Status: %{http_code}, Response Time: %{time_total}s\n" "http://$instance/metrics" --max-time 10
    
    # 5. Проверка Docker контейнера (если применимо)
    echo ""
    echo "5. Docker контейнер:"
    if docker ps | grep -q $host; then
        echo "✅ Контейнер $host запущен"
        docker ps | grep $host
    else
        echo "❌ Контейнер $host не найден или не запущен"
    fi
    
    echo ""
    echo "=== КОНЕЦ ДИАГНОСТИКИ TARGET ==="
}

# Пример использования
# diagnose_target "node-exporter" "node-exporter:9100"
```

### Исправление типичных проблем

#### 1. DNS проблемы

```bash
# Проверка DNS резолюции в Docker сети
docker exec erni-ki-prometheus nslookup node-exporter

# Исправление через добавление в /etc/hosts контейнера
docker exec -it erni-ki-prometheus sh -c "echo '172.22.0.10 node-exporter' >> /etc/hosts"

# Или исправление через docker-compose networks
```

#### 2. Сетевые проблемы

```bash
# Проверка сетевых подключений контейнера
docker inspect erni-ki-prometheus | jq '.[0].NetworkSettings.Networks'

# Добавление контейнера в нужную сеть
docker network connect erni-ki-monitoring erni-ki-prometheus
```

#### 3. Неправильные endpoints

```bash
# Проверка доступных endpoints сервиса
curl -s http://localhost:9100/ | grep -i metrics

# Исправление metrics_path в prometheus.yml
# metrics_path: /metrics  # Стандартный путь
# metrics_path: /api/v1/metrics/prometheus  # Для некоторых сервисов
```

## 🌐 HTTPS мониторинг внешних доменов

### Управление Blackbox Exporter

#### Проверка HTTPS доменов

```bash
# Проверка всех HTTPS targets
curl -s http://localhost:9091/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job == "blackbox-https")'

# Ручная проверка домена через Blackbox Exporter
curl -s "http://localhost:9115/probe?target=https://diz.zone&module=https_2xx"

# Проверка SSL сертификата
echo | openssl s_client -servername diz.zone -connect diz.zone:443 2>/dev/null | openssl x509 -noout -dates
```

#### Добавление нового домена для мониторинга

```yaml
# В monitoring/prometheus.yml добавить в blackbox-https job
- job_name: "blackbox-https"
  metrics_path: /probe
  params:
    module: [https_2xx]
  static_configs:
    - targets:
        - https://diz.zone
        - https://search.diz.zone
        - https://new-domain.example.com  # Новый домен
```

#### Мониторинг SSL сертификатов

```bash
# Скрипт проверки SSL сертификатов
cat > check_ssl.sh << 'EOF'
#!/bin/bash

DOMAINS=("diz.zone" "search.diz.zone")

echo "=== ПРОВЕРКА SSL СЕРТИФИКАТОВ ==="
echo "Время: $(date)"
echo ""

for domain in "${DOMAINS[@]}"; do
    echo "🔒 Домен: $domain"
    
    # Получение информации о сертификате
    cert_info=$(echo | openssl s_client -servername $domain -connect $domain:443 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        not_before=$(echo "$cert_info" | grep "notBefore" | cut -d= -f2)
        not_after=$(echo "$cert_info" | grep "notAfter" | cut -d= -f2)
        
        # Конвертация даты окончания в timestamp
        exp_date=$(date -d "$not_after" +%s 2>/dev/null)
        current_date=$(date +%s)
        days_left=$(( (exp_date - current_date) / 86400 ))
        
        echo "   Действителен с: $not_before"
        echo "   Действителен до: $not_after"
        echo "   Дней до истечения: $days_left"
        
        if [ $days_left -lt 30 ]; then
            echo "   ⚠️  ВНИМАНИЕ: Сертификат истекает менее чем через 30 дней!"
        elif [ $days_left -lt 7 ]; then
            echo "   🚨 КРИТИЧНО: Сертификат истекает менее чем через 7 дней!"
        else
            echo "   ✅ Сертификат действителен"
        fi
    else
        echo "   ❌ Не удалось получить информацию о сертификате"
    fi
    
    echo ""
done

echo "=== КОНЕЦ ПРОВЕРКИ ==="
EOF

chmod +x check_ssl.sh
./check_ssl.sh
```

### Диагностика Cloudflare туннелей

```bash
# Проверка статуса Cloudflared
docker logs erni-ki-cloudflared-1 --tail 20

# Проверка конфигурации туннеля
docker exec erni-ki-cloudflared-1 cloudflared tunnel info

# Тестирование доступности через туннель
curl -s -o /dev/null -w "Status: %{http_code}, Time: %{time_total}s\n" https://diz.zone/

# Проверка маршрутизации
traceroute diz.zone
```

## 🗄️ Управление Elasticsearch

### Мониторинг состояния кластера

```bash
# Проверка статуса кластера
curl -s http://localhost:9200/_cluster/health | jq '.'

# Информация об индексах
curl -s http://localhost:9200/_cat/indices?v

# Статистика узлов
curl -s http://localhost:9200/_nodes/stats | jq '.nodes[].name, .nodes[].jvm.mem'

# Проверка шаблонов индексов
curl -s http://localhost:9200/_template | jq 'keys'
```

### Обслуживание Elasticsearch

```bash
# Очистка старых индексов (старше 30 дней)
curl -X DELETE "localhost:9200/*-$(date -d '30 days ago' +%Y.%m.%d)"

# Принудительное слияние сегментов
curl -X POST "localhost:9200/_forcemerge?max_num_segments=1"

# Очистка кэша
curl -X POST "localhost:9200/_cache/clear"

# Перезагрузка настроек
curl -X POST "localhost:9200/_cluster/reroute?retry_failed=true"
```

## 🔧 Процедуры обслуживания

### Ежедневные проверки

```bash
# Создание скрипта ежедневных проверок
cat > daily_checks.sh << 'EOF'
#!/bin/bash

LOG_FILE="/var/log/erni-ki-monitoring-check.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$DATE] === ЕЖЕДНЕВНАЯ ПРОВЕРКА СИСТЕМЫ МОНИТОРИНГА ===" >> $LOG_FILE

# 1. Проверка статуса всех контейнеров
echo "[$DATE] Проверка Docker контейнеров:" >> $LOG_FILE
docker-compose -f monitoring/docker-compose.monitoring.yml ps >> $LOG_FILE

# 2. Проверка targets доступности
UP_TARGETS=$(curl -s http://localhost:9091/api/v1/targets | jq '.data.activeTargets[] | select(.health == "up")' | jq -s 'length')
TOTAL_TARGETS=$(curl -s http://localhost:9091/api/v1/targets | jq '.data.activeTargets | length')
PERCENTAGE=$(echo "scale=1; $UP_TARGETS * 100 / $TOTAL_TARGETS" | bc)

echo "[$DATE] Targets доступность: $UP_TARGETS/$TOTAL_TARGETS ($PERCENTAGE%)" >> $LOG_FILE

# 3. Проверка Elasticsearch
ES_STATUS=$(curl -s http://localhost:9200/_cluster/health | jq -r '.status')
echo "[$DATE] Elasticsearch статус: $ES_STATUS" >> $LOG_FILE

# 4. Проверка AI-сервисов
OLLAMA_STATUS=$(curl -s http://localhost:9778/metrics | grep "ollama_up" | awk '{print $2}')
echo "[$DATE] Ollama статус: $OLLAMA_STATUS" >> $LOG_FILE

# 5. Проверка дискового пространства
DISK_USAGE=$(df -h /var/lib/docker | tail -1 | awk '{print $5}')
echo "[$DATE] Использование диска Docker: $DISK_USAGE" >> $LOG_FILE

# 6. Алерты при проблемах
if [ "$PERCENTAGE" -lt "90" ]; then
    echo "[$DATE] ВНИМАНИЕ: Низкая доступность targets ($PERCENTAGE%)" >> $LOG_FILE
fi

if [ "$ES_STATUS" != "green" ]; then
    echo "[$DATE] ВНИМАНИЕ: Elasticsearch статус не green ($ES_STATUS)" >> $LOG_FILE
fi

if [ "$OLLAMA_STATUS" != "1" ]; then
    echo "[$DATE] ВНИМАНИЕ: Ollama недоступен" >> $LOG_FILE
fi

echo "[$DATE] === КОНЕЦ ЕЖЕДНЕВНОЙ ПРОВЕРКИ ===" >> $LOG_FILE
echo "" >> $LOG_FILE
EOF

chmod +x daily_checks.sh

# Добавление в crontab для ежедневного выполнения в 9:00
echo "0 9 * * * /path/to/daily_checks.sh" | crontab -
```

### Еженедельное обслуживание

```bash
# Скрипт еженедельного обслуживания
cat > weekly_maintenance.sh << 'EOF'
#!/bin/bash

echo "=== ЕЖЕНЕДЕЛЬНОЕ ОБСЛУЖИВАНИЕ СИСТЕМЫ МОНИТОРИНГА ==="
echo "Время: $(date)"

# 1. Очистка старых логов Docker
echo "1. Очистка Docker логов..."
docker system prune -f --volumes

# 2. Оптимизация Elasticsearch
echo "2. Оптимизация Elasticsearch..."
curl -X POST "localhost:9200/_forcemerge?max_num_segments=1"

# 3. Очистка старых метрик Prometheus (если нужно)
echo "3. Проверка размера данных Prometheus..."
du -sh /var/lib/docker/volumes/erni-ki_prometheus-data/_data

# 4. Проверка обновлений образов
echo "4. Проверка обновлений Docker образов..."
docker-compose -f monitoring/docker-compose.monitoring.yml pull

# 5. Резервное копирование конфигураций
echo "5. Резервное копирование конфигураций..."
tar -czf "monitoring-config-backup-$(date +%Y%m%d).tar.gz" monitoring/

echo "=== ОБСЛУЖИВАНИЕ ЗАВЕРШЕНО ==="
EOF

chmod +x weekly_maintenance.sh
```

## 🚨 Устранение неисправностей

### Типичные проблемы и решения

#### 1. Prometheus не собирает метрики

```bash
# Диагностика
curl -s http://localhost:9091/api/v1/targets | jq '.data.activeTargets[] | select(.health == "down")'

# Решение: Перезагрузка конфигурации
curl -X POST http://localhost:9091/-/reload

# Решение: Перезапуск Prometheus
docker-compose -f monitoring/docker-compose.monitoring.yml restart prometheus
```

#### 2. Grafana не показывает данные

```bash
# Проверка подключения к Prometheus
curl -s http://localhost:3000/api/datasources | jq '.'

# Проверка доступности Prometheus из Grafana
docker exec erni-ki-grafana curl -s http://prometheus:9090/api/v1/query?query=up
```

#### 3. Elasticsearch статус "yellow"

```bash
# Применение настроек single-node
curl -X PUT "localhost:9200/_all/_settings" -H 'Content-Type: application/json' -d'{"index":{"number_of_replicas":0}}'

# Проверка результата
curl -s http://localhost:9200/_cluster/health | jq '.status'
```

#### 4. Ollama Exporter не работает

```bash
# Проверка логов
docker logs erni-ki-ollama-exporter

# Проверка сетевого подключения
docker exec erni-ki-ollama-exporter curl -s http://localhost:11434/api/version

# Перезапуск с правильной конфигурацией
docker rm -f erni-ki-ollama-exporter
docker run -d --name erni-ki-ollama-exporter --network host -e OLLAMA_URL=http://localhost:11434 erni-ki-ollama-exporter:latest
```

### Процедуры восстановления

#### Полное восстановление системы мониторинга

```bash
# 1. Остановка всех сервисов
docker-compose -f monitoring/docker-compose.monitoring.yml down

# 2. Очистка данных (ОСТОРОЖНО!)
docker volume rm erni-ki_prometheus-data erni-ki_grafana-data erni-ki_elasticsearch-data

# 3. Запуск системы
docker-compose -f monitoring/docker-compose.monitoring.yml up -d

# 4. Проверка статуса
docker-compose -f monitoring/docker-compose.monitoring.yml ps

# 5. Применение конфигураций Elasticsearch
sleep 30
curl -X PUT "localhost:9200/_template/no_replicas" -H 'Content-Type: application/json' -d'{"index_patterns":["*"],"settings":{"number_of_replicas":0}}'
```

---

*Руководство по эксплуатации обновлено: 2025-08-07*  
*Версия системы мониторинга: 2.1.0*
