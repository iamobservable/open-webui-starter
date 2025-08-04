# MCP Servers Quick Reference - ERNI-KI

## 🚀 Быстрый доступ к MCP функциям

### Статус серверов
```bash
# Проверка всех серверов
for server in time postgres filesystem memory brave-search github; do
  curl -s http://localhost:8000/$server/openapi.json > /dev/null && echo "✅ $server" || echo "❌ $server"
done
```

### Доступные серверы (6/6)

| Сервер | Endpoint | Статус | Основные функции |
|--------|----------|--------|------------------|
| **Time** | :8000/time | ✅ | Время, конвертация зон |
| **PostgreSQL** | :8000/postgres | ✅ | SQL запросы к БД |
| **Filesystem** | :8000/filesystem | ✅ | Файловые операции |
| **Memory** | :8000/memory | ✅ | Граф знаний |
| **Brave Search** | :8000/brave-search | ⚠️ | Веб-поиск (нужен API ключ) |
| **GitHub** | :8000/github | ⚠️ | Git операции (нужен токен) |

---

## 📝 Примеры использования через OpenWebUI

### Временные операции
```
"Какое сейчас время в Токио?"
"Конвертируй 15:30 из Нью-Йорка в Берлинское время"
```

### База данных
```
"Покажи версию базы данных"
"Какие схемы есть в базе данных?"
```

### Файловые операции
```
"Покажи список файлов в директории /app/data"
"Создай файл test.txt с содержимым 'Hello World'"
"Найди все файлы с расширением .log"
```

### Память и знания
```
"Запомни что ERNI-KI это AI система"
"Найди информацию о ERNI-KI в памяти"
"Создай связь между ERNI-KI и OpenWebUI"
```

---

## 🔧 API примеры

### Time Server
```bash
# Текущее время
curl -X POST http://localhost:8000/time/get_current_time \
  -H "Content-Type: application/json" \
  -d '{"timezone": "Europe/Berlin"}'

# Конвертация времени
curl -X POST http://localhost:8000/time/convert_time \
  -H "Content-Type: application/json" \
  -d '{"source_timezone": "America/New_York", "time": "15:30", "target_timezone": "Europe/Berlin"}'
```

### PostgreSQL Server
```bash
# Версия БД
curl -X POST http://localhost:8000/postgres/query \
  -H "Content-Type: application/json" \
  -d '{"sql": "SELECT version()"}'

# Список схем
curl -X POST http://localhost:8000/postgres/query \
  -H "Content-Type: application/json" \
  -d '{"sql": "SELECT schema_name FROM information_schema.schemata"}'
```

### Filesystem Server
```bash
# Разрешенные директории
curl -X POST http://localhost:8000/filesystem/list_allowed_directories

# Список файлов
curl -X POST http://localhost:8000/filesystem/list_directory \
  -H "Content-Type: application/json" \
  -d '{"path": "/app/data"}'

# Создание файла
curl -X POST http://localhost:8000/filesystem/write_file \
  -H "Content-Type: application/json" \
  -d '{"path": "/app/data/test.txt", "content": "Hello World"}'

# Чтение файла
curl -X POST http://localhost:8000/filesystem/read_file \
  -H "Content-Type: application/json" \
  -d '{"path": "/app/data/test.txt"}'
```

### Memory Server
```bash
# Создание сущности
curl -X POST http://localhost:8000/memory/create_entities \
  -H "Content-Type: application/json" \
  -d '{"entities": [{"name": "ERNI-KI", "entityType": "AI System", "observations": ["Advanced AI platform"]}]}'

# Поиск в памяти
curl -X POST http://localhost:8000/memory/search_nodes \
  -H "Content-Type: application/json" \
  -d '{"query": "ERNI-KI"}'

# Чтение всего графа
curl -X POST http://localhost:8000/memory/read_graph
```

---

## 🛠️ Управление

### Перезапуск MCP сервера
```bash
docker-compose restart mcposerver
```

### Просмотр логов
```bash
docker-compose logs mcposerver --tail=50
```

### Проверка конфигурации
```bash
cat conf/mcposerver/config.json
```

### Проверка статуса контейнера
```bash
docker-compose ps mcposerver
```

---

## 🔍 Диагностика

### Проблема: Сервер не отвечает
```bash
# Проверить статус контейнера
docker-compose ps mcposerver

# Проверить логи
docker-compose logs mcposerver --tail=20

# Перезапустить
docker-compose restart mcposerver
```

### Проблема: OpenWebUI не видит инструменты
1. Проверить URL в Settings → Tools: `http://localhost:8000`
2. Убедиться что "Available Tools" показывает "1"
3. Перезагрузить страницу OpenWebUI

### Проблема: Mixed Content Error
- Используйте `http://localhost:8000` вместо `http://mcposerver:8000`
- Убедитесь что браузер разрешает небезопасный контент

---

## 📊 Производительность

- **Время запуска**: ~10 секунд
- **Память**: ~80MB
- **CPU**: <2% в idle
- **Время ответа**: <200ms

---

## 🔑 Настройка API ключей

### Brave Search
```bash
# Обновить в env/mcposerver.env
BRAVE_API_KEY=your_real_api_key

# Перезапустить
docker-compose restart mcposerver
```

### GitHub
```bash
# Обновить в env/mcposerver.env
GITHUB_PERSONAL_ACCESS_TOKEN=your_github_token

# Перезапустить
docker-compose restart mcposerver
```

---

## 📞 Поддержка

- **Документация**: `docs/mcp-servers-extended-report.md`
- **Конфигурация**: `conf/mcposerver/config.json`
- **Переменные**: `env/mcposerver.env`
- **Логи**: `docker-compose logs mcposerver`

**Статус**: ✅ 6 серверов настроены, 4 полностью функциональны  
**Обновлено**: 2025-07-19
