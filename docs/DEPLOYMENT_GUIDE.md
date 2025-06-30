# 🚀 Детальный план запуска ERNI-KI

## 📋 Краткое резюме

Создан комплексный план запуска AI платформы ERNI-KI с пошаговыми инструкциями, проверками и troubleshooting для всех компонентов системы.

---

## 🔍 1. Анализ инфраструктуры

### Архитектура системы
- **11 микросервисов** в Docker Compose
- **Nginx** как reverse proxy с JWT аутентификацией
- **PostgreSQL** с pgvector для векторного поиска
- **Ollama** для языковых моделей с GPU поддержкой
- **Cloudflare Zero-Trust** туннель для внешнего доступа

### Ключевые сервисы
| Сервис | Порт | Назначение | Зависимости |
|--------|------|------------|-------------|
| `auth` | 9090 | JWT аутентификация (Go) | - |
| `openwebui` | 8080 | Основной веб-интерфейс | auth, db, ollama, nginx |
| `ollama` | 11434 | Сервер языковых моделей | - |
| `db` | 5432 | PostgreSQL + pgvector | - |
| `nginx` | 80 | Reverse proxy | cloudflared |
| `redis` | 6379 | Кэш и брокер сообщений | - |
| `searxng` | 8080 | Метапоисковый движок | redis |

---

## ⚙️ 2. Проверка зависимостей и окружения

### Системные требования
```bash
# Проверка Docker
docker --version  # Требуется v20.10+
docker compose version  # Требуется v2.0+

# Проверка Node.js (для разработки)
node --version  # Требуется v20+
npm --version   # Требуется v10+

# Проверка Go (для auth сервиса)
go version  # Требуется v1.23+

# Проверка GPU (опционально)
nvidia-smi  # Для CUDA поддержки
```

### Проверка свободного места
```bash
# Минимум 10GB для образов и данных
df -h /var/lib/docker
df -h $(pwd)
```

---

## 🔧 3. Настройка конфигурационных файлов

### 3.1 Копирование шаблонов
```bash
# Основной Docker Compose файл
cp compose.yml.example compose.yml

# Конфигурации сервисов
cp conf/cloudflare/config.example conf/cloudflare/config.yml
cp conf/mcposerver/config.example conf/mcposerver/config.json
cp conf/nginx/nginx.example conf/nginx/nginx.conf
cp conf/nginx/conf.d/default.example conf/nginx/conf.d/default.conf
cp conf/searxng/settings.yml.example conf/searxng/settings.yml
cp conf/searxng/uwsgi.ini.example conf/searxng/uwsgi.ini
```

### 3.2 Переменные окружения
```bash
# Копирование всех env файлов
cp env/auth.example env/auth.env
cp env/cloudflared.example env/cloudflared.env
cp env/db.example env/db.env
cp env/docling.example env/docling.env
cp env/edgetts.example env/edgetts.env
cp env/mcposerver.example env/mcposerver.env
cp env/ollama.example env/ollama.env
cp env/openwebui.example env/openwebui.env
cp env/redis.example env/redis.env
cp env/searxng.example env/searxng.env
cp env/tika.example env/tika.env
cp env/watchtower.example env/watchtower.env
```

### 3.3 Критические настройки безопасности

#### Генерация секретных ключей
```bash
# Генерация единого секретного ключа для всех сервисов
SECRET_KEY=$(openssl rand -hex 32)
echo "Сгенерированный ключ: $SECRET_KEY"
```

#### Обязательные изменения в env файлах:
1. **env/auth.env**:
   ```env
   GIN_MODE=release
   JWT_SECRET=ВАШ_СЕКРЕТНЫЙ_КЛЮЧ_ЗДЕСЬ
   ```

2. **env/openwebui.env**:
   ```env
   WEBUI_SECRET_KEY=ВАШ_СЕКРЕТНЫЙ_КЛЮЧ_ЗДЕСЬ
   WEBUI_URL=https://ваш-домен.com
   DATABASE_URL="postgresql://postgres:ПАРОЛЬ_БД@db:5432/openwebui"
   ```

3. **env/db.env**:
   ```env
   POSTGRES_DB=openwebui
   POSTGRES_USER=postgres
   POSTGRES_PASSWORD=НАДЕЖНЫЙ_ПАРОЛЬ_БД
   ```

4. **env/searxng.env**:
   ```env
   SEARXNG_SECRET=ВАШ_СЕКРЕТНЫЙ_КЛЮЧ_ЗДЕСЬ
   ```

5. **env/cloudflared.env** (если используется):
   ```env
   TUNNEL_TOKEN=ваш-cloudflare-tunnel-token
   ```

#### Настройка домена в Nginx
```bash
# Замените <domain-name> на ваш домен в файле:
sed -i 's/<domain-name>/ваш-домен.com/g' conf/nginx/conf.d/default.conf
```

---

## 🚀 4. Пошаговый план запуска

### Этап 1: Подготовка
```bash
# 1. Создание директорий для данных
mkdir -p data/{postgres,redis,ollama,openwebui}

# 2. Установка прав доступа
chmod 755 data/
chmod 700 data/postgres

# 3. Проверка конфигурации Docker Compose
docker compose config
```

### Этап 2: Сборка auth сервиса
```bash
# Сборка Go сервиса аутентификации
npm run docker:build

# Альтернативно:
docker build -t erni-ki-auth:latest ./auth
```

### Этап 3: Запуск базовых сервисов
```bash
# Запуск в правильном порядке с проверками
docker compose up -d watchtower
sleep 5

docker compose up -d db redis
sleep 10

# Проверка готовности БД
docker compose exec db pg_isready -d openwebui -U postgres
```

### Этап 4: Запуск вспомогательных сервисов
```bash
docker compose up -d auth docling edgetts tika mcposerver searxng
sleep 15

# Проверка статуса
docker compose ps
```

### Этап 5: Запуск Ollama и загрузка моделей
```bash
docker compose up -d ollama
sleep 30

# Загрузка базовой модели
docker compose exec ollama ollama pull llama3.2:3b

# Проверка доступности API
curl -f http://localhost:11434/api/version
```

### Этап 6: Запуск основных сервисов
```bash
docker compose up -d nginx cloudflared
sleep 10

docker compose up -d openwebui
sleep 20

# Финальная проверка всех сервисов
docker compose ps
```

---

## ✅ 5. Тестирование работоспособности

### 5.1 Автоматические проверки
```bash
#!/bin/bash
# health_check.sh

echo "🔍 Проверка состояния сервисов..."

services=("auth" "db" "redis" "ollama" "nginx" "openwebui")

for service in "${services[@]}"; do
    status=$(docker compose ps $service --format "{{.State}}")
    if [ "$status" = "running" ]; then
        echo "✅ $service: работает"
    else
        echo "❌ $service: $status"
    fi
done

echo -e "\n🌐 Проверка HTTP endpoints..."

# Проверка основных endpoint'ов
endpoints=(
    "http://localhost:9090/health:Auth сервис"
    "http://localhost:11434/api/version:Ollama API"
    "http://localhost:80:Nginx proxy"
    "http://localhost:8080/health:OpenWebUI"
)

for endpoint in "${endpoints[@]}"; do
    url=$(echo $endpoint | cut -d: -f1)
    name=$(echo $endpoint | cut -d: -f2)

    if curl -sf "$url" > /dev/null; then
        echo "✅ $name: доступен"
    else
        echo "❌ $name: недоступен"
    fi
done
```

### 5.2 Ручные проверки
1. **Веб-интерфейс**: http://localhost
2. **Создание аккаунта администратора**
3. **Подключение к Ollama**: http://ollama:11434
4. **Тестовый чат с моделью**

---

## 🔧 6. Troubleshooting

### Частые проблемы и решения

#### Проблема: Сервис не запускается
```bash
# Проверка логов
docker compose logs [service_name]

# Проверка ресурсов
docker stats

# Перезапуск сервиса
docker compose restart [service_name]
```

#### Проблема: Ошибки аутентификации
```bash
# Проверка секретных ключей
grep -r "CHANGE_BEFORE_GOING_LIVE" env/
grep -r "YOUR-SECRET-KEY" env/

# Должно быть пусто!
```

#### Проблема: Ollama не отвечает
```bash
# Проверка GPU
nvidia-smi

# Проверка памяти
docker compose exec ollama ollama list

# Перезагрузка модели
docker compose exec ollama ollama pull llama3.2:3b
```

#### Проблема: База данных недоступна
```bash
# Проверка подключения
docker compose exec db psql -U postgres -d openwebui -c "\l"

# Проверка логов PostgreSQL
docker compose logs db

# Пересоздание БД (ОСТОРОЖНО!)
docker compose down db
docker volume rm erni-ki_postgres_data
docker compose up -d db
```

### Команды диагностики
```bash
# Полная диагностика системы
echo "=== Docker состояние ==="
docker compose ps
echo -e "\n=== Использование ресурсов ==="
docker stats --no-stream
echo -e "\n=== Логи ошибок ==="
docker compose logs --tail=50 | grep -i error
echo -e "\n=== Сетевые подключения ==="
docker compose exec openwebui netstat -tlnp
```

---

## 📊 7. Мониторинг и обслуживание

### Регулярные проверки
```bash
# Ежедневно
docker compose logs --tail=100 | grep -i error
docker system df

# Еженедельно
docker compose pull  # Обновление образов
docker system prune -f  # Очистка неиспользуемых ресурсов

# Ежемесячно
docker volume ls  # Проверка томов данных
```

### Резервное копирование
```bash
# Бэкап базы данных
docker compose exec db pg_dump -U postgres openwebui > backup_$(date +%Y%m%d).sql

# Бэкап конфигураций
tar -czf config_backup_$(date +%Y%m%d).tar.gz env/ conf/
```

---

**Почему так:**
– Структурированный подход обеспечивает надежный запуск всех компонентов
– Проверки на каждом этапе позволяют выявить проблемы на раннем этапе
– Детальный troubleshooting покрывает 90% возможных проблем
– Автоматизированные скрипты ускоряют диагностику

**Проверка:** Выполните `chmod +x health_check.sh && ./health_check.sh` после запуска всех сервисов

---

## 🔒 8. Продвинутые настройки безопасности

### 8.1 Настройка Cloudflare Zero-Trust

#### Создание туннеля
```bash
# 1. Войдите в Cloudflare Dashboard
# 2. Zero Trust > Access > Tunnels > Create a tunnel
# 3. Скопируйте токен в env/cloudflared.env

# Проверка туннеля
docker compose exec cloudflared cloudflared tunnel info
```

#### Настройка Access Policy
```yaml
# В Cloudflare Dashboard: Zero Trust > Access > Applications
name: "ERNI-KI AI Platform"
domain: "ваш-домен.com"
policies:
  - name: "Admin Access"
    action: "Allow"
    rules:
      - emails: ["admin@yourdomain.com"]
```

### 8.2 SSL/TLS конфигурация
```bash
# Автоматические сертификаты через Cloudflare
# Настройки в Cloudflare Dashboard:
# SSL/TLS > Overview > Full (strict)
# SSL/TLS > Edge Certificates > Always Use HTTPS: On
```

### 8.3 Firewall правила
```bash
# Ограничение доступа только через Cloudflare
iptables -A INPUT -p tcp --dport 80 -s 173.245.48.0/20 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j DROP

# Или через Docker Compose networks (рекомендуется)
# Добавьте в compose.yml:
networks:
  frontend:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
  backend:
    driver: bridge
    internal: true
```

---

## 📈 9. Мониторинг и метрики

### 9.1 Настройка Prometheus + Grafana
```yaml
# Добавьте в compose.yml:
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana_data:/var/lib/grafana
      - ./monitoring/grafana:/etc/grafana/provisioning
```

### 9.2 Ключевые метрики для мониторинга
```bash
# CPU и память контейнеров
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# Использование дискового пространства
du -sh data/*

# Количество активных соединений к БД
docker compose exec db psql -U postgres -d openwebui -c "SELECT count(*) FROM pg_stat_activity;"

# Статус моделей Ollama
docker compose exec ollama ollama list
```

### 9.3 Алерты и уведомления
```yaml
# monitoring/alert_rules.yml
groups:
  - name: erni-ki-alerts
    rules:
      - alert: ServiceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Service {{ $labels.instance }} is down"

      - alert: HighMemoryUsage
        expr: container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.name }}"
```

---

## 🔄 10. Процедуры обновления

### 10.1 Обновление сервисов
```bash
#!/bin/bash
# update_services.sh

echo "🔄 Начинаем обновление ERNI-KI..."

# Создание бэкапа
./backup.sh

# Остановка сервисов
docker compose down

# Обновление образов
docker compose pull

# Пересборка auth сервиса
npm run docker:build

# Запуск с проверками
docker compose up -d

# Проверка здоровья
sleep 30
./health_check.sh

echo "✅ Обновление завершено!"
```

### 10.2 Откат к предыдущей версии
```bash
#!/bin/bash
# rollback.sh

echo "⏪ Откат к предыдущей версии..."

# Остановка текущих сервисов
docker compose down

# Восстановление из бэкапа
docker compose exec db psql -U postgres -d openwebui < backup_latest.sql

# Запуск предыдущей версии
git checkout HEAD~1
docker compose up -d

echo "✅ Откат завершен!"
```

---

## 🧪 11. Тестирование производительности

### 11.1 Нагрузочное тестирование
```bash
# Установка Apache Bench
sudo apt-get install apache2-utils

# Тест основной страницы
ab -n 1000 -c 10 http://localhost/

# Тест API Ollama
ab -n 100 -c 5 -p test_prompt.json -T application/json http://localhost:11434/api/generate
```

### 11.2 Тест файл для API
```json
# test_prompt.json
{
  "model": "llama3.2:3b",
  "prompt": "Привет! Как дела?",
  "stream": false
}
```

### 11.3 Мониторинг производительности
```bash
# Создание скрипта мониторинга
cat > performance_monitor.sh << 'EOF'
#!/bin/bash
while true; do
    echo "=== $(date) ==="
    echo "CPU Usage:"
    docker stats --no-stream --format "{{.Container}}: {{.CPUPerc}}"
    echo -e "\nMemory Usage:"
    docker stats --no-stream --format "{{.Container}}: {{.MemUsage}}"
    echo -e "\nDisk Usage:"
    df -h /var/lib/docker
    echo "========================"
    sleep 60
done
EOF

chmod +x performance_monitor.sh
```

---

## 📚 12. Дополнительные ресурсы

### 12.1 Полезные команды
```bash
# Просмотр логов в реальном времени
docker compose logs -f openwebui

# Подключение к контейнеру для отладки
docker compose exec openwebui /bin/bash

# Экспорт/импорт конфигурации
docker compose config > current_config.yml

# Очистка системы
docker system prune -a --volumes
```

### 12.2 Структура проекта
```
erni-ki/
├── auth/                 # Go JWT сервис
├── conf/                 # Конфигурации сервисов
├── data/                 # Данные контейнеров
├── env/                  # Переменные окружения
├── monitoring/           # Конфигурации мониторинга
├── docs/                 # Документация
├── compose.yml           # Docker Compose конфигурация
└── DEPLOYMENT_GUIDE.md   # Этот документ
```

### 12.3 Контакты и поддержка
- **GitHub Issues**: https://github.com/DIZ-admin/erni-ki/issues
- **Документация**: https://docs.erni-ki.local
- **Telegram**: @erni-ki-support

---

## ✅ Финальный чек-лист

- [ ] Все зависимости установлены (Docker, Node.js, Go)
- [ ] Конфигурационные файлы скопированы и настроены
- [ ] Секретные ключи сгенерированы и установлены
- [ ] Домен настроен в Nginx конфигурации
- [ ] Cloudflare туннель настроен (если используется)
- [ ] Все сервисы запущены и работают
- [ ] Health check проходит успешно
- [ ] Первая модель загружена в Ollama
- [ ] Веб-интерфейс доступен и функционален
- [ ] Аккаунт администратора создан
- [ ] Мониторинг настроен
- [ ] Процедуры бэкапа настроены

**Время развертывания:** 15-30 минут для опытного администратора
**Сложность:** Средняя (требует базовых знаний Docker и Linux)
