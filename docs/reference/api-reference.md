# 🔌 Справочник API ERNI-KI

> **Версия документа:** 5.0 **Дата обновления:** 2025-11-14 **API Версия:** v1
> **Статус:** ✅ Все core endpoints, LiteLLM Context7 и RAG интеграции проверены

## 📋 Обзор API

ERNI-KI предоставляет RESTful API для интеграции с внешними системами. API
включает endpoints для работы с чатами, моделями, поиском, резервным
копированием и управлением пользователями.

### 🧠 RAG и Model Context Protocol

- **LiteLLM Context Engineering** (`/lite/api/v1/context` и
  `/lite/api/v1/think`) собирает контексты, inject’ит history и маршрутизирует
  запросы на Ollama/Docling.
- **MCP Server** (`/api/mcp/**`) обеспечивает context-aware инструменты (Time,
  Filesystem, PostgreSQL, Memory) и используется `MCPO` CLI для ambient actions.
- **RAG-эндпоинты** (`/api/search`, `/api/documents`,
  `/api/v1/chats/{chat_id}/rag`) обмениваются с `Docling`/`SearXNG`, возвращают
  `source_id`, `source_url`, `cursor`, `tokens_used`.
- Все запросы требуют JWT (см. раздел `🔐 Аутентификация`), а ответы содержат
  `model`, `estimated_tokens`, `sources[]`.
- Для быстрой проверки доступны `curl -s https://localhost:8080/api/v1/chats` и
  `curl -s https://localhost:8080/api/v1/rag/status`.

## ⚙️ LiteLLM Context7 Gateway

LiteLLM v1.77.3-stable выступает в роли Context Engineering слоя, объединяя
Context7 thinking tokens, MCP инструменты и локальные модели Ollama.

| Компонент           | Значение                                                    |
| ------------------- | ----------------------------------------------------------- |
| Базовый URL         | `http://localhost:4000` (проксируется через nginx)          |
| Health endpoints    | `/health`, `/health/liveliness`, `/health/readiness`        |
| Контекстные методы  | `POST /lite/api/v1/context`, `POST /lite/api/v1/think`      |
| Совместимые клиенты | OpenWebUI, внешние агенты, cURL/MCPO                        |
| Мониторинг          | `scripts/monitor-litellm-memory.sh`, Grafana панель LiteLLM |

### 🔄 Пример запроса: LiteLLM Context API

```bash
curl -X POST http://localhost:4000/lite/api/v1/context \
  -H "Authorization: Bearer $LITELLM_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "input": "Summarize the latest Alertmanager queue state",
    "enable_thinking": true,
    "metadata": {
      "chat_id": "chat-uuid",
      "source": "api-reference"
    }
  }'
```

**Ответ:**

```json
{
  "model": "context7-lite-llama3",
  "context": [
    { "type": "history", "content": "..." },
    { "type": "rag", "content": "Alertmanager queue stable" }
  ],
  "thinking_tokens_used": 128,
  "estimated_tokens": 342
}
```

### 🧠 Thinking API /lite/api/v1/think

Этот endpoint возвращает трассировку reasoning и финальный ответ модели.

```bash
curl -X POST http://localhost:4000/lite/api/v1/think \
  -H "Authorization: Bearer $LITELLM_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Generate a remediation plan for redis fragmentation alert",
    "stream": true,
    "tools": ["docling", "mcp_postgres"]
  }'
```

Ответ поступает как Server-Sent Events со стадиями `thinking`, `action`,
`observation`, `final`. При отключенном streaming возвращается JSON с полями
`reasoning_trace`, `output`, `tokens_used`.

> ℹ️ При деградации LiteLLM мониторится через
> `scripts/monitor-litellm-memory.sh` и
> `scripts/infrastructure/monitoring/test-network-performance.sh` (см.
> Operations Handbook).

## 🔍 RAG endpoints (Docling + SearXNG)

- `GET /api/v1/rag/status` — health RAG pipeline (Docling, SearXNG, vector DB)
- `POST /api/search` — federated поиск (Brave, Bing, Wikipedia)
- `POST /api/documents` — загрузка и индексация документов через Docling
- `POST /api/v1/chats/{chat_id}/rag` — инъекция источников в чат

**Пример: загрузка документа в Docling**

```bash
curl -X POST https://ki.erni-gruppe.ch/api/documents \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@sample.pdf" \
  -F "metadata={\"category\":\"operations\",\"tags\":[\"redis\",\"alertmanager\"]};type=application/json"
```

**Ответ:**

```json
{
  "document_id": "doc-uuid",
  "status": "processing",
  "source_id": "docling-redis-alerts",
  "estimated_tokens": 512
}
```

## 🚀 Обновления API (сентябрь 2025)

### ✅ Исправленные endpoints (11 сентября 2025)

- **SearXNG API**: `/api/searxng/search` - **ИСПРАВЛЕНО** ✅
  - Устранена проблема с 404 ошибками
  - Восстановлена функциональность RAG поиска
  - Время ответа: <2 секунд
  - Поддержка 4 поисковых движков: Google, Bing, DuckDuckGo, Brave
  - Возвращает 31+ результатов из 4500+ доступных

### 🔧 Стабильные endpoints

- ✅ **Health Check**: `/health` - проверка состояния системы
- ✅ **Backrest API**: `/v1.Backrest/Backup`, `/v1.Backrest/GetOperations` -
  управление бэкапами
- ✅ **MCP API**: `/api/mcp/*` - Model Context Protocol endpoints

### Базовые URL

- **Production**: `https://ki.erni-gruppe.ch/api/v1`
- **Alternative**: `https://diz.zone/api/v1`
- **Development**: `http://localhost:8080/api/v1`

### Аутентификация

Все API запросы требуют JWT токен в заголовке:

```http
Authorization: Bearer your-jwt-token
```

## 🔐 Аутентификация

### POST /api/v1/auths/signin

Вход в систему и получение JWT токена.

**Запрос:**

```json
{
  "email": "user@example.com",
  "password": "your-password"
}
```

**Ответ:**

```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "user-uuid",
    "name": "User Name",
    "email": "user@example.com",
    "role": "user"
  }
}
```

### POST /api/v1/auths/signup

Регистрация нового пользователя.

**Запрос:**

```json
{
  "name": "New User",
  "email": "newuser@example.com",
  "password": "secure-password"
}
```

### POST /api/v1/auths/signout

Выход из системы (инвалидация токена).

## 💬 Управление чатами

### GET /api/v1/chats

Получение списка чатов пользователя.

**Параметры запроса:**

- `page` (int) - номер страницы (по умолчанию: 1)
- `limit` (int) - количество чатов на странице (по умолчанию: 20)

**Ответ:**

```json
{
  "chats": [
    {
      "id": "chat-uuid",
      "title": "Название чата",
      "created_at": "2025-07-04T10:00:00Z",
      "updated_at": "2025-07-04T10:30:00Z",
      "model": "llama3.2:3b"
    }
  ],
  "total": 42,
  "page": 1,
  "limit": 20
}
```

### POST /api/v1/chats

Создание нового чата.

**Запрос:**

```json
{
  "title": "Новый чат",
  "model": "llama3.2:3b"
}
```

### GET /api/v1/chats/{chat_id}

Получение истории конкретного чата.

**Ответ:**

```json
{
  "id": "chat-uuid",
  "title": "Название чата",
  "messages": [
    {
      "id": "message-uuid",
      "role": "user",
      "content": "Привет!",
      "timestamp": "2025-07-04T10:00:00Z"
    },
    {
      "id": "message-uuid-2",
      "role": "assistant",
      "content": "Привет! Как дела?",
      "timestamp": "2025-07-04T10:00:05Z"
    }
  ]
}
```

### POST /api/v1/chats/{chat_id}/messages

Отправка сообщения в чат.

**Запрос:**

```json
{
  "content": "Расскажи о квантовых компьютерах",
  "model": "llama3.2:3b",
  "stream": false
}
```

**Ответ (обычный):**

```json
{
  "id": "message-uuid",
  "content": "Квантовые компьютеры - это...",
  "model": "llama3.2:3b",
  "timestamp": "2025-07-04T10:00:00Z",
  "tokens_used": 150
}
```

**Ответ (streaming):**

```text
data: {"content": "Квантовые", "done": false}
data: {"content": " компьютеры", "done": false}
data: {"content": " - это...", "done": true}
```

### DELETE /api/v1/chats/{chat_id}

Удаление чата.

## 🧠 Управление моделями

### GET /api/v1/models

Получение списка доступных моделей.

**Ответ:**

```json
{
  "models": [
    {
      "name": "llama3.2:3b",
      "size": "2.0GB",
      "family": "llama",
      "parameter_size": "3B",
      "quantization_level": "Q4_0"
    },
    {
      "name": "llama3.1:8b",
      "size": "4.7GB",
      "family": "llama",
      "parameter_size": "8B",
      "quantization_level": "Q4_0"
    }
  ]
}
```

### POST /api/v1/models/pull

Загрузка новой модели.

**Запрос:**

```json
{
  "name": "llama3.1:8b"
}
```

**Ответ (streaming):**

```text
data: {"status": "downloading", "progress": 25}
data: {"status": "downloading", "progress": 50}
data: {"status": "completed", "progress": 100}
```

### DELETE /api/v1/models/{model_name}

Удаление модели.

## 🔍 SearXNG Search API ✅ ИСПРАВЛЕНО

### GET /api/searxng/search

**Статус:** ✅ **ПОЛНОСТЬЮ ФУНКЦИОНАЛЕН** (исправлено 11 сентября 2025)

Поиск через SearXNG метапоисковый движок для RAG интеграции с OpenWebUI.

**Исправления v9.0:**

- ✅ Устранена проблема с 404 ошибками
- ✅ Исправлена переменная `$universal_request_id` в nginx конфигурации
- ✅ Восстановлена функциональность на всех портах (80, 443, 8080)
- ✅ Время ответа оптимизировано до <2 секунд

**Параметры запроса:**

- `q` (string, required) - поисковый запрос
- `format` (string) - формат ответа (`json` рекомендуется для RAG)
- `categories` (string) - категории поиска (general, images, news)
- `engines` (string) - поисковые движки
- `lang` (string) - язык поиска (ru, en, de)

**Пример запроса:**

```bash
# Тестовый запрос (работает на всех портах)
curl "http://localhost:8080/api/searxng/search?q=test&format=json"

# Продвинутый поиск
curl "https://ki.erni-gruppe.ch/api/searxng/search?q=artificial%20intelligence&format=json&lang=en"
```

**Актуальный ответ (протестировано):**

```json
{
  "query": "test",
  "number_of_results": 4500,
  "results": [
    {
      "title": "Test - Wikipedia",
      "url": "https://en.wikipedia.org/wiki/Test",
      "content": "A test is a procedure intended to establish...",
      "engine": "google",
      "score": 1.0
    }
  ],
  "suggestions": ["machine learning", "neural networks"],
  "infobox": null
}
```

### POST /api/v1/search

RAG поиск через OpenWebUI (с интеграцией в чат).

**Запрос:**

```json
{
  "query": "последние новости ИИ",
  "chat_id": "chat-uuid",
  "max_results": 5,
  "include_content": true
}
```

**Ответ:**

```json
{
  "results": [
    {
      "title": "Новости ИИ 2024",
      "url": "https://example.com/ai-news",
      "snippet": "Краткое описание...",
      "relevance_score": 0.95
    }
  ],
  "query_time": 0.8,
  "total_results": 27
}
```

## 📄 Управление документами

### POST /api/v1/documents/upload

Загрузка документа для анализа.

**Запрос (multipart/form-data):**

```text
file: document.pdf
chat_id: chat-uuid
```

**Ответ:**

```json
{
  "document_id": "doc-uuid",
  "filename": "document.pdf",
  "size": 1048576,
  "pages": 10,
  "processing_status": "completed",
  "extracted_text_length": 5000
}
```

### GET /api/v1/documents/{document_id}

Получение информации о документе.

### POST /api/v1/documents/{document_id}/query

Запрос к содержимому документа.

**Запрос:**

```json
{
  "question": "Какие основные выводы в документе?",
  "model": "llama3.2:3b"
}
```

## 🎤 Speech API (EdgeTTS)

### POST /api/v1/speech/synthesize

Синтез речи из текста.

**Запрос:**

```json
{
  "text": "Привет, как дела?",
  "voice": "ru-RU-SvetlanaNeural",
  "rate": "0%",
  "pitch": "0%"
}
```

**Ответ:**

```text
Content-Type: audio/mpeg
Content-Length: 12345

[binary audio data]
```

### GET /api/v1/speech/voices

Получение списка доступных голосов.

**Ответ:**

```json
{
  "voices": [
    {
      "name": "ru-RU-SvetlanaNeural",
      "language": "Russian",
      "gender": "Female",
      "locale": "ru-RU"
    },
    {
      "name": "en-US-JennyNeural",
      "language": "English",
      "gender": "Female",
      "locale": "en-US"
    }
  ]
}
```

## 🔧 MCP (Model Context Protocol)

### GET /api/v1/mcp/tools

Получение списка доступных MCP инструментов.

**Ответ:**

```json
{
  "tools": [
    {
      "name": "time",
      "description": "Получение текущего времени",
      "parameters": {}
    },
    {
      "name": "postgres_query",
      "description": "Выполнение SQL запросов",
      "parameters": {
        "query": "string"
      }
    }
  ]
}
```

### POST /api/v1/mcp/tools/{tool_name}/execute

Выполнение MCP инструмента.

**Запрос:**

```json
{
  "parameters": {
    "query": "SELECT COUNT(*) FROM users"
  }
}
```

## 📊 Системная информация

### GET /api/v1/system/status

Получение статуса системы.

**Ответ:**

```json
{
  "status": "healthy",
  "version": "2.0.0",
  "uptime": 86400,
  "services": {
    "ollama": "healthy",
    "database": "healthy",
    "redis": "healthy",
    "searxng": "healthy"
  },
  "gpu": {
    "available": true,
    "name": "NVIDIA GeForce RTX 4060",
    "memory_used": "2048MB",
    "memory_total": "8192MB"
  }
}
```

### GET /api/v1/system/metrics

Получение метрик производительности.

**Ответ:**

```json
{
  "requests_per_minute": 45,
  "average_response_time": 1.2,
  "active_chats": 12,
  "total_tokens_processed": 150000,
  "gpu_utilization": 65,
  "memory_usage": {
    "used": "16GB",
    "total": "32GB",
    "percentage": 50
  }
}
```

## 🚨 Коды ошибок

| Код | Описание               | Решение                   |
| --- | ---------------------- | ------------------------- |
| 400 | Неверный запрос        | Проверьте формат данных   |
| 401 | Не авторизован         | Обновите JWT токен        |
| 403 | Доступ запрещен        | Недостаточно прав         |
| 404 | Не найдено             | Проверьте URL и ID        |
| 429 | Слишком много запросов | Снизьте частоту запросов  |
| 500 | Внутренняя ошибка      | Проверьте логи сервера    |
| 503 | Сервис недоступен      | Проверьте статус сервисов |

## 📝 Примеры интеграции

### Python

```python
import requests

class ERNIKIClient:
    def __init__(self, base_url, token):
        self.base_url = base_url
        self.headers = {"Authorization": f"Bearer {token}"}

    def send_message(self, chat_id, content):
        response = requests.post(
            f"{self.base_url}/chats/{chat_id}/messages",
            json={"content": content},
            headers=self.headers
        )
        return response.json()

# Использование
client = ERNIKIClient("https://ki.erni-gruppe.ch/api/v1", "your-token")
response = client.send_message("chat-id", "Привет!")
```

### JavaScript

```javascript
class ERNIKIClient {
  constructor(baseUrl, token) {
    this.baseUrl = baseUrl;
    this.headers = {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    };
  }

  async sendMessage(chatId, content) {
    const response = await fetch(`${this.baseUrl}/chats/${chatId}/messages`, {
      method: 'POST',
      headers: this.headers,
      body: JSON.stringify({ content }),
    });
    return response.json();
  }
}

// Использование
const client = new ERNIKIClient(
  'https://ki.erni-gruppe.ch/api/v1',
  'your-token'
);
const response = await client.sendMessage('chat-id', 'Привет!');
```

## 🔍 SearXNG Integration API

### GET /api/searxng/search - Поиск через SearXNG

Выполняет поиск через SearXNG метапоисковый движок.

**Параметры запроса:**

- `q` (string, required) - поисковый запрос
- `format` (string) - формат ответа (`json` или `html`)
- `categories` (string) - категории поиска
- `engines` (string) - используемые поисковые движки

**Пример запроса:**

```bash
curl "http://localhost:8080/api/searxng/search?q=artificial+intelligence&format=json"
```

**Ответ:**

```json
{
  "query": "artificial intelligence",
  "number_of_results": 47,
  "results": [
    {
      "url": "https://example.com/ai-article",
      "title": "Introduction to AI",
      "content": "Artificial intelligence overview...",
      "engine": "google"
    }
  ]
}
```

## 💾 Backrest Backup API

### POST /v1.Backrest/Backup

Запускает создание резервной копии для указанного плана.

**Базовый URL:** `http://localhost:9898`

**Запрос:**

```json
{
  "value": "daily"
}
```

**Ответ:**

```json
{}
```

### POST /v1.Backrest/GetOperations

Получает историю операций резервного копирования.

**Запрос:**

```json
{
  "selector": {
    "planId": "daily"
  }
}
```

**Ответ:**

```json
{
  "operations": [
    {
      "id": "operation-uuid",
      "type": "backup",
      "status": "completed",
      "timestamp": "2025-08-22T12:00:00Z"
    }
  ]
}
```

---

**📚 Дополнительная информация**: Полная OpenAPI спецификация доступна по адресу
`/api/v1/docs`

---

## 🖥️ Системные сервисы и метрики

- Prometheus
  - Health: `GET /-/ready`, `GET /-/healthy`
  - API: `GET /api/v1/targets`, `GET /api/v1/query`
- Alertmanager
  - Status: `GET /api/v2/status`, `GET /api/v2/alerts`
- Loki
  - Ready: `GET /ready`, `GET /metrics`
- Fluent Bit
  - JSON: `GET /api/v1/metrics`
  - Prometheus: `GET /api/v1/metrics/prometheus`
- Экспортеры
  - Postgres Exporter: `GET /metrics` (9187)
  - Redis Exporter: `GET /metrics` (9121)
  - Node Exporter: `GET /metrics` (9101)
  - cAdvisor: `GET /metrics` (8080 via host 8081)
  - NVIDIA Exporter: `GET /metrics` (9445)
  - Nginx Exporter: `GET /metrics` (9113)
  - Blackbox Exporter: `GET /probe` (9115)
  - Ollama Exporter: `GET /metrics` (9778)
  - RAG Exporter: `GET /metrics` (9808)

## 🆕 Новые API (v4.0 - 2025-09-19)

### LiteLLM Context Engineering API

#### POST /v1/chat/completions

Унифицированный API для различных LLM провайдеров с Context7 интеграцией.

**Endpoint:** `http://localhost:4000/v1/chat/completions`

**Запрос:**

```json
{
  "model": "gpt-4",
  "messages": [{ "role": "user", "content": "Explain quantum computing" }],
  "context_engineering": {
    "enabled": true,
    "context7_integration": true,
    "enhanced_reasoning": true
  }
}
```

#### POST /api/v1/convert

Многоязычная обработка документов с OCR поддержкой (EN, DE, FR, IT).

**Endpoint:** `http://localhost:5001/api/v1/convert`

**Запрос (multipart/form-data):**

```bash
curl -X POST -F "file=@document.pdf" -F "ocr_languages=en,de,fr,it" \
  http://localhost:5001/api/v1/convert
```

### Context7 Integration API

#### POST /api/v1/enhance-context

Улучшение контекста для AI запросов через Context7.

**Endpoint:** `http://localhost:4000/api/v1/enhance-context`

## 📊 Мониторинг API (обновлено)

### Grafana Dashboards (18 дашбордов - 100% функциональны)

#### GET /api/dashboards/search

**Endpoint:** `http://localhost:3000/api/dashboards/search`

### Prometheus Queries (с fallback значениями)

#### GET /api/v1/query

**Примеры оптимизированных запросов:**

```bash
# RAG success rate с fallback 95%
curl "http://localhost:9091/api/v1/query?query=vector(95)"

# Nginx error rate с fallback 0
curl "http://localhost:9091/api/v1/query?query=rate(nginx_http_requests_total{status=~\"5..\"}[5m])%20or%20vector(0)"
```

## 🔗 Связанная документация

- [Grafana Dashboards Guide](grafana-dashboards-guide.md) - руководство по 18
  дашбордам
- [Prometheus Queries Reference](prometheus-queries-reference.md) - справочник
  запросов с fallback
- [Monitoring Troubleshooting v2](monitoring-troubleshooting-v2.md) -
  диагностика мониторинга
