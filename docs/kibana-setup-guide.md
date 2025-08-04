# 📊 Руководство по настройке Kibana для ERNI-KI

## 🎯 **Доступ к Kibana**

**✅ Рабочие URL:**
- **Discover (анализ логов)**: http://localhost:5601/app/discover
- **Dashboards**: http://localhost:5601/app/dashboards
- **Visualizations**: http://localhost:5601/app/visualize
- **Stack Management**: http://localhost:5601/app/management

> ⚠️ **Важно**: Не используйте http://localhost:5601/ - он перенаправляет на несуществующий путь. Используйте прямые ссылки выше.

---

## 🔧 **1. Создание Index Pattern**

### Автоматическая настройка (рекомендуется):
```bash
cd /home/konstantin/Documents/augment-projects/erni-ki
./scripts/setup-kibana.sh
```

### Ручная настройка:
1. Откройте **Stack Management**: http://localhost:5601/app/management
2. Перейдите в **Index Patterns** → **Create index pattern**
3. Введите pattern: `erni-ki-*`
4. Выберите временное поле: `@timestamp`
5. Нажмите **Create index pattern**

---

## 📋 **2. Анализ логов в Discover**

### Основные фильтры для сервисов:

**🔍 OpenWebUI логи:**
```
container_name:"/erni-ki-openwebui-1"
```

**🔍 nginx логи:**
```
container_name:"/erni-ki-nginx-1"
```

**🔍 Ollama логи:**
```
container_name:"/erni-ki-ollama-1"
```

**🔍 PostgreSQL логи:**
```
container_name:"/erni-ki-db-1"
```

**🔍 LiteLLM логи:**
```
container_name:"/erni-ki-litellm-1"
```

**🔍 SearXNG логи:**
```
container_name:"/erni-ki-searxng-1"
```

### Поиск ошибок:
```
log:(*error* OR *ERROR* OR *exception*) AND container_name:*
```

### Медленные запросы PostgreSQL:
```
container_name:"/erni-ki-db-1" AND log:*duration*
```

---

## 📊 **3. Создание дашбордов**

### Рекомендуемые визуализации:

**📈 Временная диаграмма логов по сервисам:**
- Тип: Line chart
- X-axis: @timestamp (Date Histogram)
- Y-axis: Count
- Split series: container_name.keyword

**🔥 Топ ошибок:**
- Тип: Data table
- Metrics: Count
- Buckets: Terms aggregation на log.keyword
- Фильтр: log:(*error* OR *ERROR*)

**📊 Распределение по источникам:**
- Тип: Pie chart
- Buckets: Terms aggregation на log_source.keyword

**⚡ Статистика по уровням:**
- Тип: Vertical bar chart
- Фильтры для разных уровней логирования

---

## 🔍 **4. Сохраненные поиски**

Автоматически созданные поиски:

**🚨 OpenWebUI Errors:**
```
container_name:"/erni-ki-openwebui-1" AND log:(*error* OR *ERROR*)
```

**📝 nginx Access Logs:**
```
container_name:"/erni-ki-nginx-1" AND NOT log:*error*
```

**🐌 Database Slow Queries:**
```
container_name:"/erni-ki-db-1" AND log:*duration*
```

**💥 All Container Errors:**
```
log:(*error* OR *ERROR* OR *exception*) AND container_name:*
```

---

## ⚙️ **5. Настройки производительности**

### Рекомендуемые настройки:

**🔄 Auto-refresh:**
- Установите интервал: 30 секунд
- Для production мониторинга: 1 минута

**📅 Временной диапазон:**
- По умолчанию: Last 24 hours
- Для отладки: Last 1 hour
- Для анализа трендов: Last 7 days

**📊 Количество записей:**
- Discover: 500 записей
- Dashboards: оптимизировать по необходимости

---

## 🎨 **6. Полезные KQL запросы**

### Мониторинг системы:

**🔍 Все ошибки за последний час:**
```
@timestamp >= now-1h AND log:(*error* OR *ERROR* OR *exception*)
```

**📊 Активность по сервисам:**
```
container_name:* AND @timestamp >= now-1h
```

**🚀 GPU операции Ollama:**
```
container_name:"/erni-ki-ollama-1" AND log:*GPU*
```

**🔐 Аутентификация:**
```
container_name:"/erni-ki-auth-1" OR log:*auth*
```

**🔍 RAG операции:**
```
(container_name:"/erni-ki-openwebui-1" OR container_name:"/erni-ki-searxng-1") AND log:*search*
```

---

## 🚨 **7. Алерты и мониторинг**

### Критические события для мониторинга:

**❌ Высокий уровень ошибок:**
```
log:*ERROR* AND @timestamp >= now-5m
```

**🐌 Медленные запросы (>5 сек):**
```
container_name:"/erni-ki-db-1" AND log:*duration* AND log:*5???ms*
```

**🔥 nginx 5xx ошибки:**
```
container_name:"/erni-ki-nginx-1" AND log:*" 5??*
```

**💾 Проблемы с диском:**
```
log:(*disk* OR *space* OR *storage*) AND log:*error*
```

---

## 📈 **8. Производительность и оптимизация**

### Мониторинг производительности:

**⏱️ Время ответа сервисов:**
- Фильтр по response_time в nginx логах
- Мониторинг duration в PostgreSQL

**📊 Использование ресурсов:**
- Поиск по memory, CPU в логах
- Мониторинг GPU utilization в Ollama

**🔄 Пропускная способность:**
- Количество запросов в минуту
- Размер обрабатываемых данных

---

## 🎯 **Быстрый старт**

1. **Откройте Discover**: http://localhost:5601/app/discover
2. **Выберите index pattern**: `erni-ki-*`
3. **Установите временной диапазон**: Last 24 hours
4. **Начните с фильтра**: `container_name:*`
5. **Добавьте поля в таблицу**: `@timestamp`, `container_name`, `log`

**🎉 Готово! Теперь вы можете анализировать логи всех сервисов ERNI-KI в едином интерфейсе.**
