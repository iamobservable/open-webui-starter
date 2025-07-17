# 👨‍💼 Руководство администратора ERNI-KI

> **Версия документа:** 3.0
> **Дата обновления:** 2025-07-15
> **Аудитория:** Системные администраторы

## 🎯 Обзор административных задач

Как администратор ERNI-KI, вы отвечаете за:
- Мониторинг состояния всех 16 сервисов (включая LiteLLM, Docling, Context Engineering)
- Управление пользователями и доступом
- Настройку резервного копирования
- Обеспечение безопасности системы
- Производительность и масштабирование
- Устранение неполадок

## 📊 Мониторинг системы

### Проверка статуса сервисов
```bash
# Общий статус всех контейнеров
docker compose ps

# Детальная информация о здоровье сервисов
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

# Проверка логов конкретного сервиса
docker compose logs -f service-name

# Мониторинг ресурсов в реальном времени
docker stats
```

### Ключевые метрики для мониторинга

#### Статус сервисов (должны быть "healthy")
- **nginx** - веб-шлюз и балансировщик
- **auth** - JWT аутентификация
- **openwebui** - основной AI интерфейс
- **ollama** - сервер языковых моделей
- **litellm** - прокси для LLM провайдеров
- **db** - PostgreSQL база данных
- **redis** - кэш и сессии
- **searxng** - поисковый движок
- **mcposerver** - Context Engineering сервер
- **docling** - обработка документов
- **tika** - извлечение метаданных
- **edgetts** - синтез речи
- **backrest** - система резервного копирования
- **cloudflared** - туннель Cloudflare
- **watchtower** - автообновление контейнеров

#### Использование ресурсов
```bash
# CPU и память по контейнерам
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

# Использование диска
df -h
docker system df

# Использование GPU (если установлен)
nvidia-smi
```

### Автоматизированный мониторинг
```bash
# Создание скрипта ежедневной проверки
cat > /usr/local/bin/erni-ki-health.sh << 'EOF'
#!/bin/bash
LOG_FILE="/var/log/erni-ki-health.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$DATE] === ERNI-KI Health Check ===" >> $LOG_FILE

# Проверка статуса контейнеров
UNHEALTHY=$(docker compose ps --format json | jq -r '.[] | select(.Health != "healthy" and .Health != "") | .Name')
if [ -n "$UNHEALTHY" ]; then
    echo "[$DATE] ⚠️  Нездоровые сервисы: $UNHEALTHY" >> $LOG_FILE
else
    echo "[$DATE] ✅ Все сервисы здоровы" >> $LOG_FILE
fi

# Проверка использования диска
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 80 ]; then
    echo "[$DATE] ⚠️  Высокое использование диска: ${DISK_USAGE}%" >> $LOG_FILE
fi

# Проверка доступности API
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/)
if [ "$HTTP_CODE" != "200" ]; then
    echo "[$DATE] ❌ OpenWebUI недоступен (HTTP $HTTP_CODE)" >> $LOG_FILE
fi
EOF

chmod +x /usr/local/bin/erni-ki-health.sh

# Добавление в crontab для ежедневного запуска
echo "0 9 * * * /usr/local/bin/erni-ki-health.sh" | crontab -
```

## 🗄️ Управление базой данных

### Подключение к PostgreSQL
```bash
# Подключение к базе данных
docker compose exec db psql -U openwebui -d openwebui

# Проверка размера базы данных
docker compose exec db psql -U openwebui -d openwebui -c "
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
"
```

### Обслуживание базы данных
```bash
# Очистка старых данных (старше 90 дней)
docker compose exec db psql -U openwebui -d openwebui -c "
DELETE FROM chat WHERE created_at < NOW() - INTERVAL '90 days';
VACUUM ANALYZE;
"

# Проверка индексов
docker compose exec db psql -U openwebui -d openwebui -c "
SELECT schemaname, tablename, indexname, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_tup_read DESC;
"

# Резервная копия базы данных
docker compose exec db pg_dump -U openwebui openwebui > backup_$(date +%Y%m%d).sql
```

## 💾 Управление резервными копиями

### Настройка Backrest
1. Откройте веб-интерфейс: `http://your-server:9898`
2. Войдите используя учетные данные из `env/backrest.env`
3. Создайте новый репозиторий для бэкапов
4. Настройте расписание резервного копирования

### Конфигурация бэкапов
```json
{
  "repos": [
    {
      "id": "local-backup",
      "uri": "/data/repositories/erni-ki",
      "password": "your-encryption-password"
    }
  ],
  "plans": [
    {
      "id": "daily-backup",
      "repo": "local-backup",
      "paths": [
        "/backup-sources/data/postgres",
        "/backup-sources/data/openwebui",
        "/backup-sources/data/redis",
        "/backup-sources/env",
        "/backup-sources/conf"
      ],
      "schedule": "0 2 * * *",
      "retention": {
        "policy": "POLICY_KEEP_N",
        "keepDaily": 7,
        "keepWeekly": 4,
        "keepMonthly": 6
      }
    }
  ]
}
```

### Восстановление из резервной копии
```bash
# Остановка сервисов
docker compose down

# Восстановление данных через Backrest UI
# или через командную строку:
docker compose exec backrest restic -r /data/repositories/erni-ki restore latest --target /

# Запуск сервисов
docker compose up -d
```

## 🔒 Безопасность и доступ

### Управление пользователями
```bash
# Создание нового пользователя через API
curl -X POST http://localhost:8080/api/v1/auths/signup \
  -H "Content-Type: application/json" \
  -d '{
    "name": "New User",
    "email": "user@example.com",
    "password": "secure-password"
  }'

# Просмотр списка пользователей (требует admin права)
docker compose exec db psql -U openwebui -d openwebui -c "
SELECT id, name, email, role, created_at FROM user ORDER BY created_at DESC;
"
```

### Настройка SSL/TLS
```bash
# Обновление SSL сертификатов
# Если используете Let's Encrypt:
certbot renew --nginx

# Если используете собственные сертификаты:
cp new-cert.pem conf/nginx/ssl/
cp new-key.pem conf/nginx/ssl/
docker compose restart nginx
```

### Аудит безопасности
```bash
# Проверка открытых портов
netstat -tulpn | grep LISTEN

# Проверка логов на подозрительную активность
docker compose logs nginx | grep -E "(40[0-9]|50[0-9])" | tail -20

# Проверка неудачных попыток входа
docker compose logs auth | grep "authentication failed" | tail -10
```

## ⚡ Производительность и оптимизация

### Мониторинг производительности
```bash
# Анализ медленных запросов PostgreSQL
docker compose exec db psql -U openwebui -d openwebui -c "
SELECT query, calls, total_time, mean_time, rows
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 10;
"

# Мониторинг Redis
docker compose exec redis redis-cli info memory
docker compose exec redis redis-cli info stats
```

### Оптимизация GPU использования
```bash
# Проверка использования GPU
nvidia-smi -l 1

# Мониторинг GPU памяти
watch -n 1 'nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits'

# Настройка лимитов GPU памяти в Ollama
docker compose exec ollama ollama show llama3.2:3b --modelfile
```

### Масштабирование сервисов
```bash
# Увеличение количества экземпляров nginx
docker compose up -d --scale nginx=2

# Мониторинг балансировки нагрузки
docker compose logs nginx | grep upstream
```

## 🔧 Устранение неполадок

### Диагностика проблем
```bash
# Проверка состояния всех сервисов
docker compose ps

# Анализ логов проблемного сервиса
docker compose logs --tail=100 service-name

# Проверка сетевого подключения между сервисами
docker compose exec nginx ping ollama
docker compose exec openwebui curl -I http://ollama:11434
```

### Типичные проблемы и решения

#### Сервис не запускается
```bash
# Проверка ресурсов
docker system df
free -h

# Очистка неиспользуемых ресурсов
docker system prune -f

# Перезапуск проблемного сервиса
docker compose restart service-name
```

#### Медленная работа AI
```bash
# Проверка загрузки GPU
nvidia-smi

# Проверка доступной памяти
free -h

# Перезапуск Ollama для очистки памяти
docker compose restart ollama
```

#### Проблемы с поиском
```bash
# Проверка SearXNG
curl "http://localhost:8080/api/searxng/search?q=test&format=json"

# Проверка Redis кэша
docker compose exec redis redis-cli ping
docker compose exec redis redis-cli info memory
```

## 📈 Планирование мощности

### Рекомендации по ресурсам

#### Для малых команд (до 10 пользователей)
- **CPU**: 8 ядер
- **RAM**: 32GB
- **GPU**: RTX 4060 (8GB VRAM)
- **Диск**: 500GB SSD

#### Для средних команд (10-50 пользователей)
- **CPU**: 16 ядер
- **RAM**: 64GB
- **GPU**: RTX 4080 (16GB VRAM)
- **Диск**: 1TB NVMe SSD

#### Для больших команд (50+ пользователей)
- **CPU**: 32+ ядер
- **RAM**: 128GB+
- **GPU**: RTX 4090 или несколько GPU
- **Диск**: 2TB+ NVMe SSD в RAID

### Мониторинг роста
```bash
# Отслеживание роста базы данных
docker compose exec db psql -U openwebui -d openwebui -c "
SELECT
    date_trunc('month', created_at) as month,
    count(*) as new_chats,
    pg_size_pretty(sum(length(content))) as total_content_size
FROM chat
GROUP BY date_trunc('month', created_at)
ORDER BY month DESC;
"
```

## 🔄 Обновления системы

### Обновление ERNI-KI
```bash
# Создание резервной копии перед обновлением
docker compose exec backrest restic backup /backup-sources

# Получение обновлений
git pull origin main

# Обновление образов Docker
docker compose pull

# Применение обновлений
docker compose up -d

# Проверка статуса после обновления
docker compose ps
```

### Откат к предыдущей версии
```bash
# Откат к предыдущему коммиту
git log --oneline -10
git checkout previous-commit-hash

# Восстановление предыдущих образов
docker compose down
docker compose up -d
```

---

**⚠️ Важно**: Всегда создавайте резервные копии перед внесением критических изменений в систему!
