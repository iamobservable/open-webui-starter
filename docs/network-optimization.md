# Сетевая оптимизация ERNI-KI

## Обзор

Данный документ описывает комплексную оптимизацию сетевой архитектуры системы ERNI-KI для достижения максимальной производительности при работе с AI сервисами, базами данных и веб-интерфейсом.

## Архитектура сетей

### Сегментация сетей

Система использует четыре изолированные сети для оптимального разделения трафика:

#### 1. Frontend сеть (erni-ki-frontend)
- **Подсеть**: 172.20.0.0/16
- **Назначение**: Внешний доступ и веб-интерфейс
- **Сервисы**: Nginx, OpenWebUI (фронтенд), Ollama (прямой доступ)
- **MTU**: 1500 (стандартный)

#### 2. Backend сеть (erni-ki-backend)  
- **Подсеть**: 172.21.0.0/16
- **Назначение**: AI сервисы и основная бизнес-логика
- **Сервисы**: LiteLLM, PostgreSQL, Redis, SearXNG, Auth
- **MTU**: 1500 (стандартный)

#### 3. Monitoring сеть (erni-ki-monitoring)
- **Подсеть**: 172.22.0.0/16  
- **Назначение**: Мониторинг и метрики
- **Сервисы**: Prometheus, Grafana, Exporters
- **MTU**: 1500 (стандартный)

#### 4. Internal сеть (erni-ki-internal)
- **Подсеть**: 172.23.0.0/16
- **Назначение**: Высокопроизводительное межсервисное взаимодействие
- **Особенности**: Изолированная сеть, Jumbo frames (MTU 9000)
- **Сервисы**: Все критические сервисы для внутреннего взаимодействия

## Статические IP адреса

### Критические сервисы

| Сервис | Frontend | Backend | Internal | Назначение |
|--------|----------|---------|----------|------------|
| Nginx | 172.20.0.10 | 172.21.0.10 | 172.23.0.10 | Реверс-прокси |
| OpenWebUI | 172.20.0.20 | 172.21.0.20 | 172.23.0.20 | Веб-интерфейс |
| LiteLLM | 172.20.0.30 | 172.21.0.30 | 172.23.0.30 | AI Gateway |
| PostgreSQL | - | 172.21.0.40 | 172.23.0.40 | База данных |
| Redis | - | 172.21.0.50 | 172.23.0.50 | Кэш и очереди |
| SearXNG | - | 172.21.0.60 | 172.23.0.60 | Поисковый движок |
| Auth | - | 172.21.0.70 | 172.23.0.70 | Аутентификация |
| Docling | - | 172.21.0.80 | 172.23.0.80 | Обработка документов |
| Ollama | 172.20.0.90 | 172.21.0.90 | 172.23.0.90 | LLM сервер |

## Оптимизации производительности

### Параметры ядра Linux

```bash
# TCP/IP буферы
net.core.rmem_max = 536870912      # 512MB
net.core.wmem_max = 536870912      # 512MB
net.ipv4.tcp_rmem = 4096 87380 536870912
net.ipv4.tcp_wmem = 4096 65536 536870912

# Соединения
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535

# TCP оптимизации
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
```

### Docker настройки

```json
{
    "default-address-pools": [
        {"base": "172.20.0.0/16", "size": 24},
        {"base": "172.21.0.0/16", "size": 24},
        {"base": "172.22.0.0/16", "size": 24},
        {"base": "172.23.0.0/16", "size": 24}
    ],
    "mtu": 1500,
    "live-restore": true,
    "max-concurrent-downloads": 10,
    "max-concurrent-uploads": 10
}
```

### Nginx upstream оптимизации

```nginx
upstream docsUpstream {
    server 172.21.0.20:8080 max_fails=5 fail_timeout=60s weight=1;
    keepalive 64;
    keepalive_requests 1000;
    keepalive_timeout 300s;
}
```

## Применение оптимизаций

### Автоматическое применение

```bash
# Запуск скрипта оптимизации (требует sudo)
sudo ./scripts/optimize-network.sh
```

### Ручное применение

1. **Остановка системы**:
```bash
docker-compose down
```

2. **Применение сетевых настроек**:
```bash
sudo sysctl -p /etc/sysctl.d/99-erni-ki-network.conf
sudo systemctl restart docker
```

3. **Создание сетей**:
```bash
docker network create --driver bridge --subnet=172.21.0.0/16 erni-ki-backend
docker network create --driver bridge --subnet=172.22.0.0/16 erni-ki-monitoring  
docker network create --driver bridge --subnet=172.23.0.0/16 --internal erni-ki-internal
```

4. **Запуск системы**:
```bash
docker-compose up -d
```

## Мониторинг производительности

### Ключевые метрики

1. **Сетевая пропускная способность**:
```bash
# Мониторинг трафика по интерфейсам
iftop -i docker0
nethogs
```

2. **Латентность между сервисами**:
```bash
# Проверка связности
docker exec erni-ki-nginx ping -c 4 172.21.0.30  # LiteLLM
docker exec erni-ki-litellm ping -c 4 172.21.0.90  # Ollama
```

3. **TCP соединения**:
```bash
# Статистика соединений
ss -tuln | grep :4000  # LiteLLM
ss -tuln | grep :11434 # Ollama
```

### Grafana дашборды

Система включает предконфигурированные дашборды для мониторинга:

- **Network Performance**: Общая производительность сети
- **Container Networking**: Сетевые метрики контейнеров  
- **AI Services Latency**: Латентность AI сервисов
- **Database Connections**: Соединения с базой данных

## Troubleshooting

### Проблемы с подключением

1. **Проверка сетей**:
```bash
docker network ls | grep erni-ki
docker network inspect erni-ki-backend
```

2. **Проверка статических IP**:
```bash
docker inspect erni-ki-litellm | grep IPAddress
docker inspect erni-ki-ollama | grep IPAddress
```

3. **Проверка портов**:
```bash
docker ps --format "table {{.Names}}\t{{.Ports}}"
```

### Проблемы с производительностью

1. **Проверка параметров ядра**:
```bash
sysctl net.core.rmem_max net.core.wmem_max
sysctl net.core.somaxconn
```

2. **Мониторинг нагрузки**:
```bash
# CPU и память
docker stats --no-stream

# Сетевая нагрузка
iftop -i docker0
```

3. **Логи производительности**:
```bash
# Nginx access logs
docker logs erni-ki-nginx-1 | tail -100

# LiteLLM performance logs  
docker logs erni-ki-litellm | grep -i "latency\|timeout"
```

## Рекомендации по настройке

### Для высокой нагрузки

1. **Увеличение лимитов**:
   - Увеличить `keepalive` соединения в Nginx
   - Поднять лимиты `rpm/tpm` в LiteLLM
   - Оптимизировать размеры буферов PostgreSQL

2. **Масштабирование**:
   - Добавить дополнительные инстансы LiteLLM
   - Использовать Redis Cluster для кэширования
   - Настроить load balancing для Ollama

### Для низкой латентности

1. **Приоритизация трафика**:
   - Использовать internal сеть для критических запросов
   - Настроить QoS на уровне хоста
   - Оптимизировать маршрутизацию в LiteLLM

2. **Кэширование**:
   - Включить кэширование в Redis
   - Настроить кэширование в Nginx
   - Использовать локальные модели Ollama

## Безопасность

### Изоляция сетей

- Internal сеть полностью изолирована от внешнего доступа
- Backend сеть доступна только через Nginx
- Monitoring сеть изолирована от пользовательского трафика

### Firewall правила

```bash
# Разрешить только необходимые порты
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS  
ufw allow 8080/tcp  # Cloudflare tunnel
ufw deny 4000/tcp   # LiteLLM (только внутренний доступ)
ufw deny 11434/tcp  # Ollama (только внутренний доступ)
```

## Заключение

Оптимизированная сетевая архитектура обеспечивает:

- **Высокую производительность**: Статические IP, оптимизированные буферы, keepalive соединения
- **Масштабируемость**: Сегментированные сети, load balancing, кэширование
- **Надежность**: Отказоустойчивость, мониторинг, автоматическое восстановление
- **Безопасность**: Изоляция сетей, контроль доступа, минимальная поверхность атаки

Регулярно мониторьте производительность и корректируйте настройки в соответствии с изменяющимися требованиями нагрузки.
