# 🔧 Руководство по диагностике проблем ERNI-KI

**Версия:** 1.0  
**Дата создания:** 2025-09-25  
**Последнее обновление:** 2025-09-25  
**Ответственный:** Tech Lead

---

## 🚨 КРИТИЧЕСКИЕ ПРОБЛЕМЫ (НЕМЕДЛЕННОЕ РЕАГИРОВАНИЕ)

### **❌ Система полностью недоступна**

#### **Симптомы:**

- Внешние домены не отвечают (ki.erni-gruppe.ch, webui.diz.zone)
- Локальный доступ http://localhost недоступен
- Множественные контейнеры в статусе "unhealthy" или "exited"

#### **Диагностика:**

```bash
# 1. Проверка статуса всех сервисов
docker compose ps

# 2. Проверка системных ресурсов
df -h  # Проверка места на диске
free -h  # Проверка памяти
nvidia-smi  # Проверка GPU

# 3. Проверка Docker
docker system df  # Использование места Docker
docker system events --since 1h  # События за последний час
```

#### **Решение:**

```bash
# 1. Экстренный перезапуск
docker compose down
docker compose up -d

# 2. Если не помогает - очистка и перезапуск
docker system prune -f
docker compose up -d --force-recreate

# 3. Крайняя мера - полная очистка
docker compose down -v
docker system prune -a -f
docker compose up -d
```

### **❌ OpenWebUI недоступен (основной интерфейс)**

#### **Симптомы:**

- http://localhost/health возвращает 502/503/504
- Пользователи не могут войти в систему
- Ошибки подключения к базе данных

#### **Диагностика:**

```bash
# 1. Проверка статуса OpenWebUI
docker compose logs openwebui --tail=50

# 2. Проверка зависимостей
docker compose ps db redis ollama

# 3. Проверка подключения к БД
docker exec erni-ki-db-1 pg_isready -U postgres

# 4. Проверка Redis
docker exec erni-ki-redis-1 redis-cli -a ErniKiRedisSecurePassword2024 ping
```

#### **Решение:**

```bash
# 1. Перезапуск зависимостей
docker compose restart db redis

# 2. Перезапуск OpenWebUI
docker compose restart openwebui

# 3. Проверка восстановления
sleep 30
curl -f http://localhost/health
```

---

## ⚠️ ЧАСТЫЕ ПРОБЛЕМЫ И РЕШЕНИЯ

### **🔴 GPU/AI Сервисы**

#### **Проблема: Ollama не использует GPU**

```bash
# Диагностика
nvidia-smi  # Проверка доступности GPU
docker exec erni-ki-ollama-1 nvidia-smi  # GPU в контейнере

# Решение
docker compose restart ollama
# Проверка использования GPU после запуска модели
docker exec erni-ki-ollama-1 nvidia-smi
```

#### **Проблема: LiteLLM возвращает ошибки 500**

```bash
# Диагностика
docker compose logs litellm --tail=30
curl -f http://localhost:4000/health

# Решение
docker compose restart litellm
sleep 15
curl -f http://localhost:4000/health
```

### **🔴 Сетевые проблемы**

#### **Проблема: Nginx 502 Bad Gateway**

```bash
# Диагностика
docker compose logs nginx --tail=20
docker exec erni-ki-nginx-1 nginx -t  # Проверка конфигурации

# Проверка upstream сервисов
curl -f http://openwebui:8080/health  # Из контейнера nginx
curl -f http://localhost:8080/health  # Прямое подключение

# Решение
docker compose restart nginx
```

#### **Проблема: Cloudflare туннели не работают**

```bash
# Диагностика
docker compose logs cloudflared --tail=20
docker exec erni-ki-cloudflared-1 nslookup nginx

# Решение
docker compose restart cloudflared
```

### **🔴 База данных**

#### **Проблема: PostgreSQL connection refused**

```bash
# Диагностика
docker compose logs db --tail=30
docker exec erni-ki-db-1 pg_isready -U postgres

# Проверка подключений
docker exec erni-ki-db-1 psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"

# Решение
docker compose restart db
sleep 10
docker exec erni-ki-db-1 pg_isready -U postgres
```

#### **Проблема: Redis connection timeout**

```bash
# Диагностика
docker compose logs redis --tail=20
docker exec erni-ki-redis-1 redis-cli -a ErniKiRedisSecurePassword2024 info

# Решение
docker compose restart redis
sleep 5
docker exec erni-ki-redis-1 redis-cli -a ErniKiRedisSecurePassword2024 ping
```

### **🔴 Мониторинг**

#### **Проблема: Prometheus не собирает метрики**

```bash
# Диагностика
curl -f http://localhost:9090/api/v1/targets  # Проверка targets
docker compose logs prometheus --tail=20

# Решение
docker exec erni-ki-prometheus promtool check config /etc/prometheus/prometheus.yml
docker compose restart prometheus
```

#### **Проблема: Grafana не показывает данные**

```bash
# Диагностика
curl -f http://localhost:3000/api/health
docker compose logs grafana --tail=20

# Решение
docker compose restart grafana
```

---

## 🔍 ДИАГНОСТИЧЕСКИЕ КОМАНДЫ

### **Системная диагностика**

```bash
# Общий статус системы
docker compose ps
docker stats --no-stream

# Использование ресурсов
df -h
free -h
nvidia-smi

# Сетевая диагностика
docker network ls
docker network inspect erni-ki_default
```

### **Диагностика логов**

```bash
# Поиск ошибок в логах за последний час
docker compose logs --since 1h | grep -i error

# Критические ошибки
docker compose logs --since 1h | grep -E "(FATAL|CRITICAL|ERROR)"

# Проблемы с подключением
docker compose logs --since 1h | grep -E "(connection|timeout|refused)"

# GPU проблемы
docker compose logs --since 1h | grep -E "(cuda|gpu|nvidia)"
```

### **Проверка конфигураций**

```bash
# Nginx конфигурация
docker exec erni-ki-nginx-1 nginx -t

# Prometheus конфигурация
docker exec erni-ki-prometheus promtool check config /etc/prometheus/prometheus.yml

# Проверка переменных окружения
docker compose config | grep -A 5 -B 5 "environment:"
```

---

## 📊 МОНИТОРИНГ ПРОИЗВОДИТЕЛЬНОСТИ

### **Ключевые метрики для отслеживания**

```bash
# CPU и память
docker stats --no-stream | head -10

# Использование GPU
nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv

# Дисковое пространство
df -h | grep -E "(/$|/var/lib/docker)"

# Сетевая активность
docker exec erni-ki-nginx-1 cat /var/log/nginx/access.log | tail -20
```

### **Проверка SLA метрик**

```bash
# Response time
curl -w "@curl-format.txt" -o /dev/null -s http://localhost/health

# Availability
curl -f http://localhost/health && echo "✅ UP" || echo "❌ DOWN"

# Error rate (из логов nginx)
docker exec erni-ki-nginx-1 tail -1000 /var/log/nginx/access.log | awk '{print $9}' | sort | uniq -c
```

---

## 🚀 ОПТИМИЗАЦИЯ ПРОИЗВОДИТЕЛЬНОСТИ

### **Когда система работает медленно**

```bash
# 1. Проверка ресурсов
docker stats --no-stream
nvidia-smi

# 2. Анализ узких мест
docker compose logs --since 10m | grep -E "(slow|timeout|high|memory)"

# 3. Оптимизация
# Перезапуск ресурсоемких сервисов
docker compose restart ollama litellm openwebui

# Очистка кэшей
docker exec erni-ki-redis-1 redis-cli -a ErniKiRedisSecurePassword2024 FLUSHDB
```

### **Профилактическое обслуживание**

```bash
# Еженедельно
docker system prune -f
docker volume prune -f

# Ежемесячно
docker compose down
docker system prune -a -f
docker compose up -d
```

---

## 📞 ЭСКАЛАЦИЯ И ПОДДЕРЖКА

### **Уровни эскалации:**

#### **Уровень 1: Самостоятельное решение (0-30 минут)**

- Использование данного руководства
- Простые перезапуски сервисов
- Проверка базовых метрик

#### **Уровень 2: Техническая поддержка (30-120 минут)**

- Анализ логов и конфигураций
- Сложная диагностика
- Rollback изменений

#### **Уровень 3: Критическая эскалация (немедленно)**

- Полная недоступность системы >30 минут
- Потеря данных
- Проблемы безопасности

### **Информация для эскалации:**

```bash
# Собрать диагностическую информацию
echo "=== SYSTEM STATUS ===" > diagnostic-$(date +%Y%m%d-%H%M%S).log
docker compose ps >> diagnostic-$(date +%Y%m%d-%H%M%S).log
echo -e "\n=== RECENT LOGS ===" >> diagnostic-$(date +%Y%m%d-%H%M%S).log
docker compose logs --since 1h --tail=100 >> diagnostic-$(date +%Y%m%d-%H%M%S).log
echo -e "\n=== SYSTEM RESOURCES ===" >> diagnostic-$(date +%Y%m%d-%H%M%S).log
df -h >> diagnostic-$(date +%Y%m%d-%H%M%S).log
free -h >> diagnostic-$(date +%Y%m%d-%H%M%S).log
nvidia-smi >> diagnostic-$(date +%Y%m%d-%H%M%S).log
```

---

## 📚 СВЯЗАННЫЕ ДОКУМЕНТЫ

- [Service Restart Procedures](service-restart-procedures.md)
- [Configuration Change Process](configuration-change-process.md)
- [Backup Restore Procedures](backup-restore-procedures.md)
- [System Monitoring Guide](../monitoring-guide.md)

---

_Документ создан в рамках оптимизации конфигураций ERNI-KI 2025-09-25_
