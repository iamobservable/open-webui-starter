# 🚀 Быстрое развертывание ERNI-KI в продакшене

> **Время развертывания:** 30-60 минут  
> **Уровень сложности:** Средний  
> **Требования:** Docker, NVIDIA GPU (опционально)

## 📋 Предварительные требования

### Системные требования
- **ОС:** Ubuntu 20.04+ / CentOS 8+ / Debian 11+
- **RAM:** Минимум 8GB, рекомендуется 16GB+
- **Диск:** Минимум 50GB свободного места
- **GPU:** NVIDIA GPU с 6GB+ VRAM (опционально, но рекомендуется)

### Программное обеспечение
```bash
# Установка Docker и Docker Compose
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Установка дополнительных утилит
sudo apt update
sudo apt install -y git curl openssl bc
```

---

## ⚡ Быстрый старт (5 минут)

### 1. Клонирование и подготовка

```bash
# Клонирование репозитория
git clone https://github.com/DIZ-admin/erni-ki.git
cd erni-ki

# Копирование конфигурационных файлов
cp compose.yml.example compose.yml
./scripts/setup.sh
```

### 2. Усиление безопасности

```bash
# Автоматическое усиление безопасности
chmod +x scripts/security-hardening.sh
./scripts/security-hardening.sh
```

**Что делает скрипт:**
- ✅ Генерирует уникальные секретные ключи
- ✅ Обновляет все файлы переменных окружения
- ✅ Создает безопасную конфигурацию Nginx
- ✅ Настраивает rate limiting и безопасные заголовки
- ✅ Создает скрипт резервного копирования

### 3. Настройка GPU (опционально)

```bash
# Настройка GPU ускорения
chmod +x scripts/gpu-setup.sh
./scripts/gpu-setup.sh

# Загрузка моделей
./scripts/gpu-setup.sh --download-models

# Тестирование производительности
./scripts/gpu-setup.sh --test-performance
```

### 4. Запуск системы

```bash
# Запуск всех сервисов
docker compose up -d

# Проверка статуса
docker compose ps

# Просмотр логов
docker compose logs -f
```

---

## 🔧 Детальная настройка

### Настройка Cloudflare туннеля

1. **Создание туннеля:**
```bash
# Установка cloudflared
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb

# Аутентификация
cloudflared tunnel login

# Создание туннеля
cloudflared tunnel create erni-ki
```

2. **Настройка DNS:**
```bash
# Добавление DNS записи
cloudflared tunnel route dns erni-ki your-domain.com
```

3. **Обновление конфигурации:**
```bash
# Добавление токена в env/cloudflared.env
echo "TUNNEL_TOKEN=your-tunnel-token-here" > env/cloudflared.env

# Обновление домена в конфигурации Nginx
sed -i 's/server_name localhost;/server_name your-domain.com;/' conf/nginx/conf.d/default.conf
```

### Настройка мониторинга

```bash
# Запуск с мониторингом
docker compose -f compose.yml -f monitoring/docker-compose.monitoring.yml up -d

# Доступ к интерфейсам:
# Grafana: http://your-domain.com:3000 (admin/admin)
# Prometheus: http://your-domain.com:9090
# Alertmanager: http://your-domain.com:9093
```

---

## 🛡️ Проверка безопасности

### Чек-лист безопасности

```bash
# Проверка секретных ключей
grep -r "CHANGE_BEFORE_GOING_LIVE" env/ || echo "✅ Секретные ключи обновлены"
grep -r "your_api_key_here" env/ || echo "✅ API ключи обновлены"

# Проверка паролей БД
grep "POSTGRES_PASSWORD=postgres" env/db.env && echo "⚠️ Пароль БД не изменен" || echo "✅ Пароль БД обновлен"

# Проверка конфигурации Nginx
nginx -t -c conf/nginx/nginx.conf && echo "✅ Конфигурация Nginx корректна"

# Проверка SSL сертификатов
curl -I https://your-domain.com | grep "HTTP/2 200" && echo "✅ HTTPS работает"
```

### Тестирование безопасности

```bash
# Тест rate limiting
for i in {1..20}; do curl -s -o /dev/null -w "%{http_code}\n" http://your-domain.com/; done

# Проверка заголовков безопасности
curl -I http://your-domain.com | grep -E "(X-Frame-Options|X-Content-Type-Options|X-XSS-Protection)"

# Сканирование портов
nmap -sS -O your-domain.com
```

---

## 📊 Мониторинг и алерты

### Основные метрики для отслеживания

| Метрика | Нормальное значение | Критическое значение |
|---------|-------------------|---------------------|
| **CPU Usage** | <70% | >90% |
| **Memory Usage** | <80% | >95% |
| **Disk Usage** | <80% | >90% |
| **Response Time** | <2s | >5s |
| **Error Rate** | <1% | >5% |
| **GPU Memory** | <90% | >95% |

### Настройка алертов

```bash
# Настройка Discord уведомлений
echo 'WATCHTOWER_NOTIFICATION_URL="discord://token@channel"' >> env/watchtower.env

# Настройка email уведомлений в Alertmanager
cat >> monitoring/alertmanager.yml << 'EOF'
global:
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: 'alerts@your-domain.com'
  smtp_auth_username: 'your-email@gmail.com'
  smtp_auth_password: 'your-app-password'
EOF
```

---

## 🔄 Резервное копирование

### Автоматические бэкапы

```bash
# Настройка ежедневных бэкапов
sudo crontab -e

# Добавить строку:
0 2 * * * /path/to/erni-ki/scripts/backup.sh

# Ручной бэкап
./scripts/backup.sh
```

### Восстановление из бэкапа

```bash
# Остановка сервисов
docker compose down

# Восстановление PostgreSQL
docker compose up -d db
docker compose exec -T db psql -U postgres -d openwebui < backup/postgres_backup.sql

# Восстановление Redis
docker compose up -d redis
docker compose exec -T redis redis-cli --pipe < backup/redis_backup.rdb

# Восстановление конфигураций
tar -xzf backup/configs.tar.gz

# Восстановление данных
tar -xzf backup/data.tar.gz

# Запуск всех сервисов
docker compose up -d
```

---

## 🚨 Устранение неполадок

### Частые проблемы

#### 1. Ollama не запускается
```bash
# Проверка логов
docker compose logs ollama

# Проверка GPU
nvidia-smi

# Перезапуск с отладкой
docker compose stop ollama
docker compose up ollama
```

#### 2. Open WebUI недоступен
```bash
# Проверка зависимостей
docker compose ps

# Проверка подключения к БД
docker compose exec db psql -U postgres -d openwebui -c "SELECT 1;"

# Проверка переменных окружения
docker compose exec openwebui env | grep -E "(DATABASE_URL|OLLAMA_BASE_URLS)"
```

#### 3. Nginx возвращает 502
```bash
# Проверка upstream серверов
docker compose exec nginx nginx -t

# Проверка доступности сервисов
docker compose exec nginx curl -f http://openwebui:8080/health
docker compose exec nginx curl -f http://auth:9090/health
```

#### 4. Высокое использование ресурсов
```bash
# Мониторинг ресурсов
docker stats

# Ограничение ресурсов
docker compose down
# Добавить в compose.yml:
# deploy:
#   resources:
#     limits:
#       memory: 2G
#       cpus: '1.0'
docker compose up -d
```

---

## 📈 Оптимизация производительности

### Настройки для высокой нагрузки

```yaml
# Добавить в compose.yml для масштабирования
services:
  openwebui:
    deploy:
      replicas: 3
      resources:
        limits:
          memory: 4G
          cpus: '2.0'
        reservations:
          memory: 2G
          cpus: '1.0'
```

### Кэширование

```bash
# Настройка Redis кэширования
echo "REDIS_CACHE_TTL=3600" >> env/openwebui.env
echo "ENABLE_REDIS_CACHE=true" >> env/openwebui.env
```

---

## ✅ Финальная проверка

### Контрольный список готовности

- [ ] Все сервисы запущены и здоровы
- [ ] Секретные ключи изменены
- [ ] HTTPS настроен через Cloudflare
- [ ] GPU ускорение работает (если применимо)
- [ ] Мониторинг настроен
- [ ] Бэкапы настроены
- [ ] Алерты настроены
- [ ] Производительность протестирована

### Команды для проверки

```bash
# Проверка всех сервисов
docker compose ps | grep -v "Exit"

# Проверка доступности
curl -f https://your-domain.com/health

# Проверка GPU (если применимо)
docker compose exec ollama nvidia-smi

# Проверка производительности
time docker compose exec ollama ollama run llama3.2:3b "Hello, world!"
```

---

## 🎯 Следующие шаги

1. **Мониторинг:** Настройте дашборды Grafana для вашей команды
2. **Масштабирование:** Добавьте load balancer для высокой доступности
3. **Безопасность:** Внедрите WAF и DDoS защиту
4. **Автоматизация:** Настройте CI/CD для автоматических обновлений
5. **Документация:** Создайте внутреннюю документацию для команды

**Поздравляем! 🎉 ERNI-KI готов к использованию в продакшене!**
