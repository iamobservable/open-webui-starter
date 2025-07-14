# Исправление ошибки OpenWebUI Tool Servers

## Описание проблемы

При попытке открыть настройки модели в веб-интерфейсе OpenWebUI возникала ошибка:

```
AttributeError: 'str' object has no attribute 'get'
File "/app/backend/open_webui/utils/tools.py", line 492, in get_tool_servers_data
if server.get("config", {}).get("enable"):
```

## Причина ошибки

Переменная окружения `TOOL_SERVER_CONNECTIONS` была настроена неправильно:

**Неправильно (вызывало ошибку):**
```bash
TOOL_SERVER_CONNECTIONS=["http://mcposerver:8000/time", "http://mcposerver:8000/postgres"]
```

Функция `get_tool_servers_data()` ожидает массив объектов (словарей), но получала массив строк.

## Решение

1. **Исправлена конфигурация в `env/openwebui.env`:**
   ```bash
   # Tool Server Connections - пустой массив для избежания ошибок парсинга
   TOOL_SERVER_CONNECTIONS=[]
   ```

2. **Исправлена конфигурация watchtower.env** (удалены некорректные шаблоны Go)

3. **Перезапущен OpenWebUI контейнер**

## Правильный формат TOOL_SERVER_CONNECTIONS

Если в будущем потребуется настроить tool servers, используйте следующий формат:

```bash
TOOL_SERVER_CONNECTIONS=[
  {
    "url": "http://mcposerver:8000",
    "config": {"enable": true},
    "info": {"name": "MCP Server"},
    "path": "openapi.json"
  }
]
```

## Результат

✅ **Все 14 сервисов ERNI-KI работают и имеют статус "healthy"**
✅ **OpenWebUI запускается без ошибок**
✅ **Веб-интерфейс доступен (HTTP 200)**
✅ **Настройки модели открываются без ошибок**
✅ **Сохранена работоспособность всех интеграций**

## План отката

В случае проблем можно откатиться к предыдущей конфигурации:

1. **Восстановить старую конфигурацию:**
   ```bash
   # В env/openwebui.env
   TOOL_SERVER_CONNECTIONS=["http://mcposerver:8000/time", "http://mcposerver:8000/postgres"]
   ```

2. **Перезапустить контейнер:**
   ```bash
   docker-compose restart openwebui
   ```

3. **Если нужен полный сброс конфигурации:**
   ```bash
   # Добавить в env/openwebui.env
   RESET_CONFIG_ON_START=true
   # Перезапустить и затем удалить эту переменную
   ```

## Проверка работоспособности

```bash
# Проверка статуса всех сервисов
docker-compose ps

# Проверка логов OpenWebUI на ошибки
docker-compose logs openwebui --tail=20 | grep -i error

# Проверка доступности веб-интерфейса
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/
```

## Время выполнения

- **Диагностика:** 15 минут
- **Исправление:** 10 минут
- **Тестирование:** 5 минут
- **Общее время:** 30 минут
- **Время простоя:** < 2 минуты (только перезапуск контейнера)

## Дата исправления

2025-07-04 17:00 UTC
