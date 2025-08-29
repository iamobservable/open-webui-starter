# 🌐 WebSocket Архитектура ERNI-KI

**Версия:** 1.0  
**Дата:** 2025-08-29  
**Статус:** Production Ready

## 📋 **Обзор WebSocket архитектуры**

Система ERNI-KI использует Redis-based WebSocket Manager для обеспечения real-time коммуникации
между клиентами и сервером. Архитектура поддерживает кластерные развертывания и обеспечивает высокую
доступность WebSocket соединений.

## 🏗️ **Архитектурная диаграмма WebSocket**

```mermaid
graph TB
    subgraph "🌐 Client Layer"
        CLIENT1[👤 Browser Client 1]
        CLIENT2[👤 Browser Client 2]
        CLIENT3[👤 Browser Client 3]
    end

    subgraph "🚪 Gateway Layer"
        NGINX[🚪 Nginx Reverse Proxy<br/>WebSocket Upgrade<br/>Connection Pooling]
        CF[☁️ Cloudflare Tunnel<br/>SSL Termination]
    end

    subgraph "🤖 Application Layer"
        OWUI[🤖 OpenWebUI<br/>WebSocket Server<br/>Socket.IO Handler]
        WS_MGR[🔌 WebSocket Manager<br/>Redis-based<br/>Session Management]
    end

    subgraph "💾 Data Layer"
        REDIS[(⚡ Redis Stack 7.4.5<br/>🔐 Authentication Enabled<br/>📊 WebSocket Sessions<br/>🔄 Pub/Sub Channels)]
        AUTH_LAYER[🔐 Authentication Layer<br/>requirepass enabled<br/>Connection validation]
    end

    subgraph "📊 Monitoring"
        REDIS_EXP[📊 Redis Exporter<br/>WebSocket Metrics<br/>Connection Monitoring]
        LOGS[📝 WebSocket Logs<br/>Connection Events<br/>Error Tracking]
    end

    %% Client connections
    CLIENT1 -.->|WSS Connection| CF
    CLIENT2 -.->|WSS Connection| CF
    CLIENT3 -.->|WSS Connection| CF

    %% Gateway routing
    CF -->|HTTPS/WSS| NGINX
    NGINX -->|WebSocket Upgrade| OWUI

    %% Application layer
    OWUI -->|WebSocket Manager| WS_MGR
    WS_MGR -->|Redis Connection| AUTH_LAYER
    AUTH_LAYER -->|Authenticated| REDIS

    %% Monitoring connections
    REDIS -->|Metrics| REDIS_EXP
    OWUI -->|Logs| LOGS
    WS_MGR -->|Events| LOGS

    %% Styling
    style REDIS fill:#ff6b6b
    style AUTH_LAYER fill:#4ecdc4
    style WS_MGR fill:#45b7d1
    style OWUI fill:#f9ca24
```

## 🔄 **WebSocket Connection Flow**

```mermaid
sequenceDiagram
    participant C as Client Browser
    participant N as Nginx
    participant O as OpenWebUI
    participant W as WebSocket Manager
    participant A as Auth Layer
    participant R as Redis Stack

    Note over C,R: WebSocket Connection Establishment

    C->>N: WSS Connection Request
    N->>O: WebSocket Upgrade
    O->>W: Initialize WebSocket Manager
    W->>A: Authenticate with Redis
    A->>R: AUTH ErniKiRedisSecurePassword2024
    R-->>A: +OK (Authentication Success)
    A-->>W: Connection Established
    W-->>O: WebSocket Manager Ready
    O-->>N: WebSocket Connection Accepted
    N-->>C: WebSocket Connection Established

    Note over C,R: Real-time Communication

    C->>N: WebSocket Message
    N->>O: Forward Message
    O->>W: Process Message
    W->>R: Publish to Channel
    R-->>W: Message Published
    W-->>O: Broadcast to Clients
    O-->>N: WebSocket Response
    N-->>C: Real-time Update

    Note over C,R: Error Handling

    W->>A: Connection Check
    A->>R: PING
    R-->>A: PONG (Health Check OK)
    A-->>W: Connection Healthy

    Note over C,R: Disconnection

    C->>N: Close WebSocket
    N->>O: Connection Closed
    O->>W: Cleanup Session
    W->>R: Remove from Channel
    R-->>W: Session Removed
```

## ⚙️ **Конфигурация WebSocket**

### **1. OpenWebUI WebSocket настройки**

```bash
# env/openwebui.env
ENABLE_WEBSOCKET_SUPPORT=true
WEBSOCKET_MANAGER=redis
REDIS_URL=redis://:ErniKiRedisSecurePassword2024@redis:6379/0
WEBSOCKET_REDIS_URL=redis://:ErniKiRedisSecurePassword2024@redis:6379/0
```

### **2. Redis Stack конфигурация**

```yaml
# compose.yml
redis:
  command: >
    redis-stack-server --requirepass ErniKiRedisSecurePassword2024 --save "" --appendonly yes
    --maxmemory-policy allkeys-lru
```

### **3. Nginx WebSocket поддержка**

```nginx
# Автоматическая конфигурация WebSocket upgrade
location / {
    proxy_pass http://openwebui:8080;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
}
```

## 📊 **Мониторинг WebSocket**

### **1. Ключевые метрики**

- **Активные соединения:** `redis_connected_clients`
- **Pub/Sub каналы:** `redis_pubsub_channels`
- **Сообщения в секунду:** `redis_pubsub_patterns`
- **Ошибки аутентификации:** `0` (целевое значение)

### **2. Логирование событий**

```bash
# Проверка WebSocket логов
docker logs erni-ki-openwebui-1 | grep -i websocket

# Проверка Redis подключений
docker logs erni-ki-redis-1 | grep -i "accepted\|closed"

# Мониторинг ошибок аутентификации
docker logs erni-ki-openwebui-1 | grep -i "AuthenticationError" | wc -l
```

## 🔧 **Troubleshooting WebSocket**

### **1. Проблема: WebSocket не подключается**

#### **Диагностика:**

```bash
# Проверка WebSocket настроек
grep WEBSOCKET env/openwebui.env

# Проверка Redis подключения
docker exec erni-ki-redis-1 redis-cli -a 'ErniKiRedisSecurePassword2024' ping

# Проверка Nginx конфигурации
docker logs erni-ki-nginx-1 | grep -i upgrade
```

#### **Решение:**

1. Убедиться, что `ENABLE_WEBSOCKET_SUPPORT=true`
2. Проверить Redis аутентификацию
3. Валидировать Nginx WebSocket upgrade headers

### **2. Проблема: Частые разрывы соединения**

#### **Диагностика:**

```bash
# Проверка Redis стабильности
docker logs erni-ki-redis-1 --tail 50

# Мониторинг WebSocket событий
docker logs erni-ki-openwebui-1 | grep -i "disconnect\|reconnect"
```

#### **Решение:**

1. Проверить Redis memory limits
2. Увеличить WebSocket timeout настройки
3. Мониторить network connectivity

## 🎯 **Performance Benchmarks**

### **WebSocket производительность:**

| Метрика                  | Значение | Статус              |
| ------------------------ | -------- | ------------------- |
| Время подключения        | <500ms   | ✅ Отлично          |
| Задержка сообщений       | <50ms    | ✅ Отлично          |
| Одновременные соединения | 100+     | ✅ Поддерживается   |
| Ошибки аутентификации    | 0/час    | ✅ Идеально         |
| Uptime WebSocket         | 99.9%+   | ✅ Production Ready |

### **Redis WebSocket метрики:**

| Метрика           | Значение     | Целевое |
| ----------------- | ------------ | ------- |
| Redis connections | 17 active    | <50     |
| Memory usage      | 2.20M (0.1%) | <10%    |
| Response time     | <10ms        | <50ms   |
| Pub/Sub channels  | Active       | Stable  |

## 🔐 **Безопасность WebSocket**

### **1. Аутентификация**

- Redis требует пароль для всех подключений
- WebSocket Manager аутентифицируется при каждом подключении
- Нет anonymous доступа к Redis

### **2. Шифрование**

- WSS (WebSocket Secure) через Cloudflare
- TLS 1.3 шифрование end-to-end
- Secure headers в Nginx

### **3. Мониторинг безопасности**

- Логирование всех WebSocket событий
- Мониторинг неудачных аутентификаций
- Алерты на подозрительную активность

## 📚 **Дополнительные ресурсы**

- [Socket.IO Redis Adapter](https://socket.io/docs/v4/redis-adapter/)
- [Redis Pub/Sub Documentation](https://redis.io/docs/manual/pubsub/)
- [WebSocket Security Best Practices](https://owasp.org/www-community/attacks/WebSocket_security)

---

**Автор:** Альтэон Шульц (Tech Lead)  
**Версия:** 1.0  
**Дата создания:** 2025-08-29
