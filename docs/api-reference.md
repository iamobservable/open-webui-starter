# 🔌 Справочник API ERNI-KI

> **Версия документа:** 2.0 **Дата обновления:** 2025-07-04 **API Версия:** v1

## 📋 Обзор API

ERNI-KI предоставляет RESTful API для интеграции с внешними системами. API
включает endpoints для работы с чатами, моделями, поиском и управлением
пользователями.

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

```
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

```
data: {"status": "downloading", "progress": 25}
data: {"status": "downloading", "progress": 50}
data: {"status": "completed", "progress": 100}
```

### DELETE /api/v1/models/{model_name}

Удаление модели.

## 🔍 SearXNG Search API

### GET /api/searxng/search

Поиск через SearXNG (прямой доступ).

**Параметры запроса:**

- `q` (string) - поисковый запрос
- `format` (string) - формат ответа (json, html)
- `categories` (string) - категории поиска
- `engines` (string) - поисковые движки
- `lang` (string) - язык поиска (ru, en)

**Пример запроса:**

```http
GET /api/searxng/search?q=artificial%20intelligence&format=json&lang=ru
```

**Ответ:**

```json
{
  "query": "artificial intelligence",
  "number_of_results": 27,
  "results": [
    {
      "title": "Искусственный интеллект — Википедия",
      "url": "https://ru.wikipedia.org/wiki/Искусственный_интеллект",
      "content": "Искусственный интеллект (ИИ) — свойство...",
      "engine": "wikipedia",
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

```
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

```
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

---

**📚 Дополнительная информация**: Полная OpenAPI спецификация доступна по адресу
`/api/v1/docs`
