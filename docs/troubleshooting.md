# 🔧 Troubleshooting Guide - ERNI-KI

> **Версия:** 5.0 **Дата обновления:** 04.08.2025 **Статус:** Production Ready

## 📋 Обзор

Comprehensive руководство по диагностике и решению проблем в системе ERNI-KI с
архитектурой 20+ сервисов.

## ✅ Недавно решенные проблемы

### SearXNG RAG интеграция (Август 2025)

**Проблема:** SearXNG возвращал 0 результатов поиска, RAG не работал

**Причина:** CAPTCHA блокировка от DuckDuckGo и Google

**Решение:**

```bash
# 1. Отключить проблемные движки в конфигурации
vim conf/searxng/settings.yml
# Установить disabled: true для duckduckgo

# 2. Перезапустить SearXNG
docker restart erni-ki-searxng-1

# 3. Проверить работу
curl -s "http://localhost:8080/search?q=test&format=json&engines=startpage" | jq '.results | length'
```

**Результат:** ✅ 60+ результатов за <3 секунды

### Backrest API (Август 2025)

**Проблема:** API endpoints возвращали 404 ошибки

**Причина:** Неправильные REST endpoints

**Решение:**

```bash
# Использовать правильные JSON RPC endpoints
curl -X POST 'http://localhost:9898/v1.Backrest/GetOperations' \
  --data '{}' -H 'Content-Type: application/json'

curl -X POST 'http://localhost:9898/v1.Backrest/GetConfig' \
  --data '{}' -H 'Content-Type: application/json'
```

**Результат:** ✅ API полностью функционален

## 🚨 Быстрая диагностика

### Автоматическая диагностика

```bash
# Автоматическое восстановление
./scripts/troubleshooting/automated-recovery.sh

# Быстрая проверка здоровья
./scripts/maintenance/health-check.sh

# Исправление критических проблем
./scripts/troubleshooting/fix-critical-issues.sh
```

### Проверка статуса сервисов

```bash
# Статус всех контейнеров
docker compose ps

# Проверка логов
docker compose logs --tail=50

# Использование ресурсов
docker stats --no-stream
```

## 🔍 Диагностика по сервисам

### OpenWebUI

**Проблема:** Интерфейс недоступен

```bash
# Проверка статуса
docker compose ps openwebui

# Проверка логов
docker compose logs openwebui

# Перезапуск сервиса
docker compose restart openwebui
```

**Проблема:** Ошибки аутентификации

```bash
# Проверка базы данных
docker compose exec postgres psql -U postgres -d openwebui -c "\dt"

# Сброс пароля администратора
docker compose exec openwebui python manage.py reset_admin_password
```

### Ollama

**Проблема:** Модели не загружаются

```bash
# Проверка доступных моделей
docker compose exec ollama ollama list

# Проверка использования GPU
./scripts/performance/gpu-monitor.sh

# Загрузка модели вручную
docker compose exec ollama ollama pull llama2
```

**Проблема:** Медленная генерация

```bash
# Проверка GPU
nvidia-smi

# Тест производительности GPU
./scripts/performance/gpu-performance-test.sh

# Проверка настроек GPU
cat env/ollama.env | grep GPU
```

### PostgreSQL

**Проблема:** База данных недоступна

```bash
# Проверка статуса
docker compose ps postgres

# Проверка подключения
docker compose exec postgres pg_isready -U postgres

# Проверка логов
docker compose logs postgres
```

**Проблема:** Проблемы с производительностью

```bash
# Проверка активных подключений
docker compose exec postgres psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"

# Проверка размера базы данных
docker compose exec postgres psql -U postgres -c "\l+"
```

### SearXNG

**Проблема:** Поиск не работает

```bash
# Тест интеграции SearXNG
./scripts/troubleshooting/test-searxng-integration.sh

# Проверка API
curl -s "http://localhost:8080/search?q=test&format=json" | jq .

# Проверка конфигурации
docker compose exec searxng cat /etc/searxng/settings.yml
```

### Nginx

**Проблема:** 502 Bad Gateway

```bash
# Проверка конфигурации nginx
docker compose exec nginx nginx -t

# Проверка upstream серверов
docker compose exec nginx cat /etc/nginx/conf.d/default.conf

# Перезагрузка конфигурации
docker compose exec nginx nginx -s reload
```

### Redis

**Проблема:** Кэш не работает

```bash
# Проверка подключения к Redis
docker compose exec redis redis-cli ping

# Проверка использования памяти
docker compose exec redis redis-cli info memory

# Очистка кэша
docker compose exec redis redis-cli flushall
```

## 🌐 Сетевые проблемы

### Проблемы с доступом

```bash
# Тест сетевой связности
./scripts/troubleshooting/test-network-simple.sh

# Проверка портов
netstat -tlnp | grep -E "(80|443|8080)"

# Проверка DNS
nslookup your-domain.com
```

### Cloudflare Tunnel

```bash
# Проверка статуса tunnel
docker compose logs cloudflared

# Проверка конфигурации
cat env/cloudflared.env

# Перезапуск tunnel
docker compose restart cloudflared
```

## 🔒 Проблемы безопасности

### SSL/TLS проблемы

```bash
# Проверка сертификата
openssl x509 -in conf/ssl/cert.pem -text -noout

# Тест SSL подключения
openssl s_client -connect your-domain.com:443

# Генерация новых сертификатов
./conf/ssl/generate-ssl-certs.sh
```

### Проблемы аутентификации

```bash
# Проверка JWT токенов
docker compose logs auth-server

# Сброс секретов
./scripts/security/rotate-secrets.sh

# Проверка настроек безопасности
./scripts/security/security-monitor.sh
```

## 💾 Проблемы с данными

### Backup проблемы

```bash
# Проверка статуса backup
./scripts/backup/check-local-backup.sh

# Тест backup
./scripts/backup/backrest-management.sh test

# Восстановление из backup
./scripts/backup/backrest-management.sh restore --date=latest
```

### Проблемы с дисковым пространством

```bash
# Проверка использования диска
df -h

# Очистка Docker
docker system prune -f

# Очистка логов
./scripts/maintenance/log-rotation-manager.sh
```

## ⚡ Проблемы производительности

### Высокое использование CPU

```bash
# Мониторинг процессов
top -p $(docker inspect --format='{{.State.Pid}}' $(docker compose ps -q))

# Анализ производительности
./scripts/performance/hardware-analysis.sh

# Оптимизация ресурсов
docker compose up -d --scale worker=2
```

### Проблемы с памятью

```bash
# Проверка использования памяти
free -h

# Мониторинг памяти контейнеров
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# Очистка кэшей
echo 3 | sudo tee /proc/sys/vm/drop_caches
```

### GPU проблемы

```bash
# Проверка драйверов NVIDIA
nvidia-smi

# Тест GPU в Docker
docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu20.04 nvidia-smi

# Диагностика GPU в Ollama
./scripts/troubleshooting/test-healthcheck.sh
```

## 🔄 Процедуры восстановления

### Мягкий перезапуск

```bash
# Корректный перезапуск
./scripts/maintenance/graceful-restart.sh

# Проверка после перезапуска
./scripts/maintenance/health-check.sh
```

### Жесткий перезапуск

```bash
# Остановка всех сервисов
docker compose down

# Очистка сетей и volumes (осторожно!)
docker network prune -f
docker volume prune -f

# Запуск системы
docker compose up -d
```

### Восстановление из backup

```bash
# Остановка системы
docker compose down

# Восстановление данных
./scripts/backup/backrest-management.sh restore

# Запуск системы
docker compose up -d
```

## 📊 Мониторинг и алерты

### Webhook Receiver

**Проблема:** Алерты не доставляются

```bash
# Проверка статуса webhook-receiver
docker compose ps webhook-receiver

# Проверка логов
docker compose logs webhook-receiver --tail=20

# Тестирование endpoint
curl -X POST http://localhost:9095/webhook \
  -H "Content-Type: application/json" \
  -d '{"alerts":[{"status":"firing","labels":{"alertname":"TestAlert"}}]}'

# Проверка health endpoint
curl -s http://localhost:9095/health

# Перезапуск сервиса
docker compose restart webhook-receiver
```

### GPU мониторинг

**Проблема:** GPU метрики недоступны

```bash
# Проверка NVIDIA GPU Exporter
curl -s http://localhost:9445/metrics | grep nvidia_gpu

# Проверка GPU статуса
nvidia-smi

# Перезапуск GPU exporter
docker compose restart nvidia-exporter

# Проверка GPU в контейнере
docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu20.04 nvidia-smi
```

### Настройка алертов

```bash
# Проверка AlertManager
curl -s http://localhost:9093/api/v1/alerts

# Тест уведомлений
./scripts/troubleshooting/test-watchtower-notifications.sh

# Настройка webhook
nano monitoring/alertmanager.yml
```

### Анализ метрик

```bash
# Экспорт метрик Prometheus
curl -s http://localhost:9091/metrics

# Проверка Grafana dashboard
curl -s http://localhost:3000/api/health

# Анализ производительности
./scripts/performance/monitoring-system-status.sh
```

## 🆘 Emergency Procedures

### Критический сбой системы

1. **Немедленная диагностика:**

   ```bash
   ./scripts/troubleshooting/automated-recovery.sh
   ```

2. **Проверка критических сервисов:**

   ```bash
   docker compose ps | grep -E "(postgres|ollama|openwebui)"
   ```

3. **Восстановление из backup:**
   ```bash
   ./scripts/backup/backrest-management.sh emergency-restore
   ```

### Потеря данных

1. **Остановка записи:**

   ```bash
   docker compose stop openwebui
   ```

2. **Восстановление из backup:**

   ```bash
   ./scripts/backup/backrest-management.sh restore --date=latest
   ```

3. **Проверка целостности:**
   ```bash
   ./scripts/troubleshooting/test-healthcheck.sh
   ```

## 📞 Получение помощи

### Сбор диагностической информации

```bash
# Создание диагностического отчета
./scripts/troubleshooting/automated-recovery.sh --report

# Экспорт логов
docker compose logs > system-logs-$(date +%Y%m%d).txt

# Экспорт конфигураций
tar -czf config-backup-$(date +%Y%m%d).tar.gz env/ conf/
```

### Контакты поддержки

- **📖 Документация:** [docs/](../)
- **🐛 Issues:** [GitHub Issues](https://github.com/DIZ-admin/erni-ki/issues)
- **💬 Discussions:**
  [GitHub Discussions](https://github.com/DIZ-admin/erni-ki/discussions)
- **🔧 Emergency:** Создайте issue с тегом `critical`

---

**📝 Примечание:** При создании issue приложите диагностический отчет и логи для
быстрого решения проблемы.
