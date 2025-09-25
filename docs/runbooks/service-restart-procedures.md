# 🔄 Процедуры перезапуска сервисов ERNI-KI

**Версия:** 1.0  
**Дата создания:** 2025-09-25  
**Последнее обновление:** 2025-09-25  
**Ответственный:** Tech Lead

---

## 📋 ОБЩИЕ ПРИНЦИПЫ

### ✅ **Перед перезапуском ВСЕГДА:**

1. **Создать backup** текущих конфигураций
2. **Проверить статус** зависимых сервисов
3. **Уведомить пользователей** о плановом обслуживании
4. **Подготовить rollback план** на случай проблем

### ⚠️ **Порядок перезапуска (критически важно):**

1. **Auxiliary сервисы** (EdgeTTS, Tika, Docling)
2. **Monitoring сервисы** (Exporters, Fluent-bit)
3. **Infrastructure сервисы** (Redis, PostgreSQL)
4. **AI сервисы** (Ollama, LiteLLM)
5. **Critical сервисы** (OpenWebUI, Nginx)

---

## 🚨 ЭКСТРЕННЫЙ ПЕРЕЗАПУСК (КРИТИЧЕСКИЕ ПРОБЛЕМЫ)

### **Полный перезапуск системы**

```bash
# 1. Создать emergency backup
BACKUP_DIR=".config-backup/emergency-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
sudo cp -r env/ conf/ compose.yml "$BACKUP_DIR/"

# 2. Остановить все сервисы
docker compose down

# 3. Очистить логи (опционально)
docker system prune -f --volumes

# 4. Запустить систему
docker compose up -d

# 5. Проверить статус
docker compose ps
docker compose logs --tail=50
```

### **Перезапуск критических сервисов**

```bash
# OpenWebUI (основной интерфейс)
docker compose restart openwebui
docker compose logs openwebui --tail=20

# Nginx (reverse proxy)
docker compose restart nginx
docker compose logs nginx --tail=20

# PostgreSQL (база данных)
docker compose restart db
docker compose logs db --tail=20
```

---

## 🔧 ПЛАНОВЫЙ ПЕРЕЗАПУСК СЕРВИСОВ

### **1. AUXILIARY СЕРВИСЫ (низкий приоритет)**

#### **EdgeTTS (Text-to-Speech)**

```bash
# Проверка статуса
docker compose ps edgetts
curl -f http://localhost:5050/health || echo "EdgeTTS недоступен"

# Перезапуск
docker compose restart edgetts

# Проверка после перезапуска
sleep 10
docker compose logs edgetts --tail=10
curl -f http://localhost:5050/health && echo "EdgeTTS восстановлен"
```

#### **Apache Tika (документы)**

```bash
# Проверка статуса
docker compose ps tika
curl -f http://localhost:9998/tika || echo "Tika недоступен"

# Перезапуск
docker compose restart tika

# Проверка после перезапуска
sleep 15
docker compose logs tika --tail=10
curl -f http://localhost:9998/tika && echo "Tika восстановлен"
```

#### **Docling (OCR)**

```bash
# Проверка статуса
docker compose ps docling
curl -f http://localhost:5001/health || echo "Docling недоступен"

# Перезапуск
docker compose restart docling

# Проверка после перезапуска
sleep 20
docker compose logs docling --tail=10
curl -f http://localhost:5001/health && echo "Docling восстановлен"
```

### **2. MONITORING СЕРВИСЫ**

#### **Prometheus (метрики)**

```bash
# Проверка конфигурации
docker exec erni-ki-prometheus promtool check config /etc/prometheus/prometheus.yml

# Перезапуск
docker compose restart prometheus

# Проверка после перезапуска
sleep 10
curl -f http://localhost:9090/-/healthy && echo "Prometheus восстановлен"
```

#### **Grafana (дашборды)**

```bash
# Перезапуск
docker compose restart grafana

# Проверка после перезапуска
sleep 15
curl -f http://localhost:3000/api/health && echo "Grafana восстановлен"
```

### **3. INFRASTRUCTURE СЕРВИСЫ**

#### **Redis (кэш)**

```bash
# Проверка статуса
docker exec erni-ki-redis-1 redis-cli -a ErniKiRedisSecurePassword2024 ping

# Перезапуск
docker compose restart redis

# Проверка после перезапуска
sleep 5
docker exec erni-ki-redis-1 redis-cli -a ErniKiRedisSecurePassword2024 ping
```

#### **PostgreSQL (база данных)**

```bash
# ВНИМАНИЕ: Критический сервис! Уведомить пользователей!

# Проверка статуса
docker exec erni-ki-db-1 pg_isready -U postgres

# Создать backup БД
docker exec erni-ki-db-1 pg_dump -U postgres openwebui > backup-$(date +%Y%m%d-%H%M%S).sql

# Перезапуск
docker compose restart db

# Проверка после перезапуска
sleep 10
docker exec erni-ki-db-1 pg_isready -U postgres
```

### **4. AI СЕРВИСЫ**

#### **Ollama (LLM сервер)**

```bash
# ВНИМАНИЕ: GPU сервис! Проверить NVIDIA драйверы!

# Проверка GPU
nvidia-smi

# Проверка статуса Ollama
curl -f http://localhost:11434/api/tags || echo "Ollama недоступен"

# Перезапуск
docker compose restart ollama

# Проверка после перезапуска (может занять до 60 секунд)
sleep 30
curl -f http://localhost:11434/api/tags && echo "Ollama восстановлен"

# Проверка GPU использования
docker exec erni-ki-ollama-1 nvidia-smi
```

#### **LiteLLM (AI Gateway)**

```bash
# Проверка статуса
curl -f http://localhost:4000/health || echo "LiteLLM недоступен"

# Перезапуск
docker compose restart litellm

# Проверка после перезапуска
sleep 15
curl -f http://localhost:4000/health && echo "LiteLLM восстановлен"
```

### **5. CRITICAL СЕРВИСЫ**

#### **OpenWebUI (основной интерфейс)**

```bash
# ВНИМАНИЕ: Основной пользовательский интерфейс!

# Проверка зависимостей
docker compose ps db redis ollama

# Перезапуск
docker compose restart openwebui

# Проверка после перезапуска
sleep 20
curl -f http://localhost:8080/health && echo "OpenWebUI восстановлен"

# Проверка через nginx
curl -f http://localhost/health && echo "OpenWebUI доступен через nginx"
```

#### **Nginx (reverse proxy)**

```bash
# ВНИМАНИЕ: Критический сервис для внешнего доступа!

# Проверка конфигурации
docker exec erni-ki-nginx-1 nginx -t

# Перезапуск
docker compose restart nginx

# Проверка после перезапуска
sleep 5
curl -I http://localhost && echo "Nginx восстановлен"
curl -I https://localhost && echo "HTTPS работает"
```

---

## 🔍 ПРОВЕРКА ПОСЛЕ ПЕРЕЗАПУСКА

### **Автоматическая проверка всех сервисов**

```bash
#!/bin/bash
# Скрипт проверки здоровья системы после перезапуска

echo "=== ПРОВЕРКА СТАТУСА СЕРВИСОВ ==="
docker compose ps

echo -e "\n=== ПРОВЕРКА КРИТИЧЕСКИХ ENDPOINTS ==="
curl -f http://localhost/health && echo "✅ OpenWebUI доступен" || echo "❌ OpenWebUI недоступен"
curl -f http://localhost:11434/api/tags && echo "✅ Ollama работает" || echo "❌ Ollama недоступен"
curl -f http://localhost:9090/-/healthy && echo "✅ Prometheus работает" || echo "❌ Prometheus недоступен"

echo -e "\n=== ПРОВЕРКА ВНЕШНЕГО ДОСТУПА ==="
curl -s -I https://ki.erni-gruppe.ch/health | head -1 && echo "✅ Внешний доступ работает" || echo "❌ Внешний доступ недоступен"

echo -e "\n=== ПРОВЕРКА GPU ==="
docker exec erni-ki-ollama-1 nvidia-smi | grep "NVIDIA-SMI" && echo "✅ GPU доступен" || echo "❌ GPU недоступен"

echo -e "\n=== ПРОВЕРКА ЛОГОВ НА ОШИБКИ ==="
docker compose logs --tail=100 | grep -i error | tail -5
```

---

## 📞 ЭСКАЛАЦИЯ ПРОБЛЕМ

### **Уровень 1: Автоматическое восстановление**

- Простой перезапуск сервиса
- Проверка логов
- Базовая диагностика

### **Уровень 2: Ручное вмешательство**

- Анализ конфигураций
- Проверка зависимостей
- Rollback к предыдущей версии

### **Уровень 3: Критическая эскалация**

- Полное восстановление из backup
- Контакт с Tech Lead
- Документирование инцидента

---

## 📚 СВЯЗАННЫЕ ДОКУМЕНТЫ

- [Troubleshooting Guide](troubleshooting-guide.md)
- [Configuration Change Process](configuration-change-process.md)
- [Backup Restore Procedures](backup-restore-procedures.md)
- [System Architecture](../architecture.md)

---

_Документ создан в рамках оптимизации конфигураций ERNI-KI 2025-09-25_
