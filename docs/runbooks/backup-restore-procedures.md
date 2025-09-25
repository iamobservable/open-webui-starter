# 💾 Процедуры резервного копирования и восстановления ERNI-KI

**Версия:** 1.0  
**Дата создания:** 2025-09-25  
**Последнее обновление:** 2025-09-25  
**Ответственный:** Tech Lead

---

## 📋 ОБЩИЕ ПРИНЦИПЫ

### ✅ **Стратегия резервного копирования:**

- **Ежедневные backup'ы** критических данных (7 дней хранения)
- **Еженедельные backup'ы** полной системы (4 недели хранения)
- **Перед изменениями** - обязательные snapshot'ы
- **Тестирование восстановления** - ежемесячно

### 📂 **Что включается в backup:**

- **Конфигурации:** `env/`, `conf/`, `compose.yml`
- **База данных:** PostgreSQL (OpenWebUI данные)
- **Пользовательские данные:** OpenWebUI uploads, модели Ollama
- **Логи:** Критические логи за последние 7 дней
- **Сертификаты:** SSL сертификаты и ключи

---

## 🔄 АВТОМАТИЧЕСКОЕ РЕЗЕРВНОЕ КОПИРОВАНИЕ (BACKREST)

### **Текущая конфигурация Backrest**

```bash
# Проверка статуса Backrest
docker compose ps backrest
curl -f http://localhost:9898/api/v1/status

# Просмотр конфигурации
docker exec erni-ki-backrest-1 cat /config/config.json
```

### **Мониторинг автоматических backup'ов**

```bash
# Проверка последних backup'ов
curl -s http://localhost:9898/api/v1/repos | jq '.[] | {name: .name, lastBackup: .lastBackup}'

# Проверка логов Backrest
docker compose logs backrest --tail=50

# Проверка размера backup'ов
du -sh .config-backup/
```

### **Настройка уведомлений о backup'ах**

```bash
# Создать скрипт проверки backup'ов
cat > check-backups.sh << 'EOF'
#!/bin/bash
WEBHOOK_URL="YOUR_WEBHOOK_URL"  # Настроить webhook для уведомлений

# Проверка последнего backup'а
LAST_BACKUP=$(curl -s http://localhost:9898/api/v1/repos | jq -r '.[0].lastBackup')
CURRENT_TIME=$(date +%s)
BACKUP_TIME=$(date -d "$LAST_BACKUP" +%s)
HOURS_DIFF=$(( (CURRENT_TIME - BACKUP_TIME) / 3600 ))

if [ $HOURS_DIFF -gt 25 ]; then
    echo "⚠️ ВНИМАНИЕ: Последний backup был $HOURS_DIFF часов назад!"
    # Отправить уведомление
    curl -X POST "$WEBHOOK_URL" -d "Backup ERNI-KI устарел: $HOURS_DIFF часов"
else
    echo "✅ Backup актуален (последний: $HOURS_DIFF часов назад)"
fi
EOF

chmod +x check-backups.sh

# Добавить в crontab для ежедневной проверки
echo "0 9 * * * /path/to/check-backups.sh" | crontab -
```

---

## 📦 РУЧНОЕ РЕЗЕРВНОЕ КОПИРОВАНИЕ

### **Полный backup системы**

```bash
#!/bin/bash
# Скрипт полного backup'а ERNI-KI

BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=".config-backup/full-backup-$BACKUP_DATE"

echo "🔄 Создание полного backup'а в $BACKUP_DIR"

# 1. Создать директорию
mkdir -p "$BACKUP_DIR"

# 2. Остановить сервисы для консистентности (опционально)
read -p "Остановить сервисы для консистентного backup'а? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Остановка сервисов..."
    docker compose stop openwebui litellm
    SERVICES_STOPPED=true
fi

# 3. Backup конфигураций
echo "Backup конфигураций..."
sudo cp -r env/ "$BACKUP_DIR/"
sudo cp -r conf/ "$BACKUP_DIR/"
cp compose.yml "$BACKUP_DIR/"

# 4. Backup базы данных
echo "Backup базы данных..."
docker exec erni-ki-db-1 pg_dump -U postgres -Fc openwebui > "$BACKUP_DIR/database.dump"
docker exec erni-ki-db-1 pg_dumpall -U postgres > "$BACKUP_DIR/database-full.sql"

# 5. Backup пользовательских данных OpenWebUI
echo "Backup пользовательских данных..."
sudo cp -r data/openwebui/ "$BACKUP_DIR/" 2>/dev/null || echo "OpenWebUI data не найдена"

# 6. Backup моделей Ollama
echo "Backup моделей Ollama..."
sudo cp -r data/ollama/ "$BACKUP_DIR/" 2>/dev/null || echo "Ollama data не найдена"

# 7. Backup критических логов
echo "Backup логов..."
mkdir -p "$BACKUP_DIR/logs"
docker compose logs --since 7d > "$BACKUP_DIR/logs/services-7days.log"

# 8. Создать манифест backup'а
cat > "$BACKUP_DIR/backup-manifest.txt" << EOF
ERNI-KI Full Backup
Дата создания: $(date)
Версия системы: $(docker compose version)
Статус сервисов на момент backup'а:
$(docker compose ps)

Содержимое backup'а:
- Конфигурации: env/, conf/, compose.yml
- База данных: PostgreSQL dump (binary и SQL)
- Пользовательские данные: OpenWebUI, Ollama
- Логи: 7 дней истории
- Размер backup'а: $(du -sh "$BACKUP_DIR" | cut -f1)
EOF

# 9. Запустить сервисы обратно
if [ "$SERVICES_STOPPED" = true ]; then
    echo "Запуск сервисов..."
    docker compose up -d
fi

# 10. Создать архив (опционально)
read -p "Создать tar.gz архив? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Создание архива..."
    tar -czf "$BACKUP_DIR.tar.gz" -C .config-backup "full-backup-$BACKUP_DATE"
    echo "Архив создан: $BACKUP_DIR.tar.gz"
fi

echo "✅ Полный backup завершен: $BACKUP_DIR"
echo "📄 Манифест: $BACKUP_DIR/backup-manifest.txt"
```

### **Быстрый backup конфигураций**

```bash
#!/bin/bash
# Быстрый backup только конфигураций (без остановки сервисов)

BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=".config-backup/config-backup-$BACKUP_DATE"

echo "🔄 Создание backup'а конфигураций в $BACKUP_DIR"

mkdir -p "$BACKUP_DIR"
sudo cp -r env/ "$BACKUP_DIR/"
sudo cp -r conf/ "$BACKUP_DIR/"
cp compose.yml "$BACKUP_DIR/"

# Создать snapshot текущего состояния
docker compose ps > "$BACKUP_DIR/services-status.txt"
docker compose config > "$BACKUP_DIR/compose-resolved.yml"

echo "✅ Backup конфигураций завершен: $BACKUP_DIR"
```

### **Backup только базы данных**

```bash
#!/bin/bash
# Backup только PostgreSQL базы данных

BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=".config-backup/db-backup-$BACKUP_DATE"

echo "🔄 Создание backup'а базы данных в $BACKUP_DIR"

mkdir -p "$BACKUP_DIR"

# Binary dump (быстрое восстановление)
docker exec erni-ki-db-1 pg_dump -U postgres -Fc openwebui > "$BACKUP_DIR/openwebui.dump"

# SQL dump (читаемый формат)
docker exec erni-ki-db-1 pg_dump -U postgres openwebui > "$BACKUP_DIR/openwebui.sql"

# Полный dump всех баз
docker exec erni-ki-db-1 pg_dumpall -U postgres > "$BACKUP_DIR/all-databases.sql"

# Информация о базе
docker exec erni-ki-db-1 psql -U postgres -c "\l" > "$BACKUP_DIR/database-info.txt"
docker exec erni-ki-db-1 psql -U postgres -d openwebui -c "\dt" > "$BACKUP_DIR/tables-info.txt"

echo "✅ Backup базы данных завершен: $BACKUP_DIR"
```

---

## 🔄 ПРОЦЕДУРЫ ВОССТАНОВЛЕНИЯ

### **Полное восстановление системы**

```bash
#!/bin/bash
# Полное восстановление ERNI-KI из backup'а

BACKUP_DIR="$1"
if [ -z "$BACKUP_DIR" ]; then
    echo "Usage: $0 <backup_directory>"
    echo "Доступные backup'ы:"
    ls -la .config-backup/ | grep full-backup
    exit 1
fi

if [ ! -d "$BACKUP_DIR" ]; then
    echo "❌ Backup директория не найдена: $BACKUP_DIR"
    exit 1
fi

echo "🔄 Начинаем полное восстановление из $BACKUP_DIR"
echo "⚠️  ВНИМАНИЕ: Это перезапишет все текущие данные!"
read -p "Продолжить? (yes/no): " -r
if [[ ! $REPLY =~ ^yes$ ]]; then
    echo "Восстановление отменено"
    exit 1
fi

# 1. Остановить все сервисы
echo "Остановка сервисов..."
docker compose down

# 2. Создать backup текущего состояния
echo "Создание backup текущего состояния..."
CURRENT_BACKUP=".config-backup/pre-restore-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$CURRENT_BACKUP"
sudo cp -r env/ conf/ compose.yml "$CURRENT_BACKUP/" 2>/dev/null || true

# 3. Восстановить конфигурации
echo "Восстановление конфигураций..."
sudo rm -rf env/ conf/
sudo cp -r "$BACKUP_DIR/env/" ./
sudo cp -r "$BACKUP_DIR/conf/" ./
cp "$BACKUP_DIR/compose.yml" ./

# 4. Восстановить права доступа
sudo chown -R $USER:$USER env/ conf/

# 5. Запустить базовые сервисы
echo "Запуск базовых сервисов..."
docker compose up -d db redis

# 6. Ждать готовности базы данных
echo "Ожидание готовности базы данных..."
sleep 30
until docker exec erni-ki-db-1 pg_isready -U postgres; do
    echo "Ожидание PostgreSQL..."
    sleep 5
done

# 7. Восстановить базу данных
if [ -f "$BACKUP_DIR/database.dump" ]; then
    echo "Восстановление базы данных из binary dump..."
    docker exec erni-ki-db-1 dropdb -U postgres openwebui --if-exists
    docker exec erni-ki-db-1 createdb -U postgres openwebui
    docker exec -i erni-ki-db-1 pg_restore -U postgres -d openwebui < "$BACKUP_DIR/database.dump"
elif [ -f "$BACKUP_DIR/database-full.sql" ]; then
    echo "Восстановление базы данных из SQL dump..."
    docker exec -i erni-ki-db-1 psql -U postgres < "$BACKUP_DIR/database-full.sql"
else
    echo "⚠️ Backup базы данных не найден"
fi

# 8. Восстановить пользовательские данные
if [ -d "$BACKUP_DIR/openwebui" ]; then
    echo "Восстановление пользовательских данных OpenWebUI..."
    sudo rm -rf data/openwebui/
    sudo cp -r "$BACKUP_DIR/openwebui/" data/
fi

if [ -d "$BACKUP_DIR/ollama" ]; then
    echo "Восстановление моделей Ollama..."
    sudo rm -rf data/ollama/
    sudo cp -r "$BACKUP_DIR/ollama/" data/
fi

# 9. Запустить все сервисы
echo "Запуск всех сервисов..."
docker compose up -d

# 10. Проверить восстановление
echo "Проверка восстановления..."
sleep 60

echo "=== СТАТУС СЕРВИСОВ ==="
docker compose ps

echo -e "\n=== ПРОВЕРКА ДОСТУПНОСТИ ==="
curl -f http://localhost/health && echo "✅ OpenWebUI доступен" || echo "❌ OpenWebUI недоступен"
curl -f http://localhost:11434/api/tags && echo "✅ Ollama работает" || echo "❌ Ollama недоступен"

echo -e "\n✅ Восстановление завершено!"
echo "📄 Backup текущего состояния (до восстановления): $CURRENT_BACKUP"
echo "📄 Манифест восстановленного backup'а: $BACKUP_DIR/backup-manifest.txt"
```

### **Восстановление только конфигураций**

```bash
#!/bin/bash
# Восстановление только конфигураций без остановки сервисов

BACKUP_DIR="$1"
if [ -z "$BACKUP_DIR" ]; then
    echo "Usage: $0 <backup_directory>"
    exit 1
fi

echo "🔄 Восстановление конфигураций из $BACKUP_DIR"

# Создать backup текущих конфигураций
CURRENT_BACKUP=".config-backup/pre-config-restore-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$CURRENT_BACKUP"
sudo cp -r env/ conf/ compose.yml "$CURRENT_BACKUP/"

# Восстановить конфигурации
sudo cp -r "$BACKUP_DIR/env/" ./
sudo cp -r "$BACKUP_DIR/conf/" ./
cp "$BACKUP_DIR/compose.yml" ./

# Применить изменения
docker compose up -d --no-recreate

echo "✅ Конфигурации восстановлены"
echo "📄 Backup предыдущих конфигураций: $CURRENT_BACKUP"
```

### **Восстановление только базы данных**

```bash
#!/bin/bash
# Восстановление только PostgreSQL базы данных

BACKUP_FILE="$1"
if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup_file>"
    echo "Поддерживаемые форматы: .dump, .sql"
    exit 1
fi

echo "🔄 Восстановление базы данных из $BACKUP_FILE"
echo "⚠️  ВНИМАНИЕ: Это перезапишет текущую базу данных!"
read -p "Продолжить? (yes/no): " -r
if [[ ! $REPLY =~ ^yes$ ]]; then
    echo "Восстановление отменено"
    exit 1
fi

# Создать backup текущей базы
echo "Создание backup текущей базы..."
CURRENT_DB_BACKUP=".config-backup/db-pre-restore-$(date +%Y%m%d-%H%M%S).dump"
docker exec erni-ki-db-1 pg_dump -U postgres -Fc openwebui > "$CURRENT_DB_BACKUP"

# Восстановить базу данных
if [[ "$BACKUP_FILE" == *.dump ]]; then
    echo "Восстановление из binary dump..."
    docker exec erni-ki-db-1 dropdb -U postgres openwebui --if-exists
    docker exec erni-ki-db-1 createdb -U postgres openwebui
    docker exec -i erni-ki-db-1 pg_restore -U postgres -d openwebui < "$BACKUP_FILE"
elif [[ "$BACKUP_FILE" == *.sql ]]; then
    echo "Восстановление из SQL dump..."
    docker exec -i erni-ki-db-1 psql -U postgres < "$BACKUP_FILE"
else
    echo "❌ Неподдерживаемый формат файла"
    exit 1
fi

# Перезапустить сервисы, использующие базу данных
echo "Перезапуск сервисов..."
docker compose restart openwebui litellm

echo "✅ База данных восстановлена"
echo "📄 Backup предыдущей базы: $CURRENT_DB_BACKUP"
```

---

## 🧪 ТЕСТИРОВАНИЕ BACKUP'ОВ

### **Ежемесячная проверка восстановления**

```bash
#!/bin/bash
# Скрипт тестирования процедуры восстановления

echo "🧪 Тестирование процедуры восстановления"

# 1. Найти последний backup
LATEST_BACKUP=$(ls -t .config-backup/full-backup-* | head -1)
echo "Тестируем backup: $LATEST_BACKUP"

# 2. Создать тестовую среду
TEST_DIR="test-restore-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# 3. Скопировать backup
cp -r "../$LATEST_BACKUP" ./

# 4. Создать минимальную тестовую конфигурацию
# [здесь можно создать упрощенную версию для тестирования]

# 5. Протестировать восстановление конфигураций
echo "Тестирование восстановления конфигураций..."
# [выполнить тестовое восстановление]

# 6. Создать отчет
cat > restore-test-report.txt << EOF
Отчет о тестировании восстановления
Дата: $(date)
Тестируемый backup: $LATEST_BACKUP
Статус: [УСПЕШНО/НЕУДАЧНО]
Проблемы: [описание проблем]
Рекомендации: [рекомендации по улучшению]
EOF

echo "✅ Тестирование завершено"
echo "📄 Отчет: $TEST_DIR/restore-test-report.txt"
```

---

## 📊 МОНИТОРИНГ BACKUP'ОВ

### **Дашборд статуса backup'ов**

```bash
#!/bin/bash
# Создать дашборд статуса backup'ов

echo "📊 СТАТУС РЕЗЕРВНОГО КОПИРОВАНИЯ ERNI-KI"
echo "========================================"
echo "Дата: $(date)"
echo

# Статус Backrest
echo "🔄 АВТОМАТИЧЕСКИЕ BACKUP'Ы (Backrest):"
if curl -f http://localhost:9898/api/v1/status >/dev/null 2>&1; then
    echo "✅ Backrest сервис работает"
    LAST_BACKUP=$(curl -s http://localhost:9898/api/v1/repos | jq -r '.[0].lastBackup' 2>/dev/null)
    if [ "$LAST_BACKUP" != "null" ] && [ -n "$LAST_BACKUP" ]; then
        echo "📅 Последний backup: $LAST_BACKUP"
    else
        echo "⚠️ Информация о последнем backup недоступна"
    fi
else
    echo "❌ Backrest сервис недоступен"
fi

# Ручные backup'ы
echo -e "\n💾 РУЧНЫЕ BACKUP'Ы:"
BACKUP_COUNT=$(ls -1 .config-backup/full-backup-* 2>/dev/null | wc -l)
echo "📦 Количество полных backup'ов: $BACKUP_COUNT"

if [ $BACKUP_COUNT -gt 0 ]; then
    LATEST_MANUAL=$(ls -t .config-backup/full-backup-* | head -1)
    LATEST_DATE=$(basename "$LATEST_MANUAL" | sed 's/full-backup-//')
    echo "📅 Последний ручной backup: $LATEST_DATE"
fi

# Размер backup'ов
echo -e "\n💽 ИСПОЛЬЗОВАНИЕ МЕСТА:"
BACKUP_SIZE=$(du -sh .config-backup/ 2>/dev/null | cut -f1)
echo "📊 Общий размер backup'ов: $BACKUP_SIZE"

# Рекомендации
echo -e "\n💡 РЕКОМЕНДАЦИИ:"
if [ $BACKUP_COUNT -lt 3 ]; then
    echo "⚠️ Рекомендуется создать больше backup'ов"
fi

DAYS_SINCE_BACKUP=$(find .config-backup/ -name "full-backup-*" -mtime -7 | wc -l)
if [ $DAYS_SINCE_BACKUP -eq 0 ]; then
    echo "⚠️ Не было backup'ов за последние 7 дней"
fi

echo -e "\n✅ Проверка завершена"
```

---

## 📚 СВЯЗАННЫЕ ДОКУМЕНТЫ

- [Service Restart Procedures](service-restart-procedures.md)
- [Troubleshooting Guide](troubleshooting-guide.md)
- [Configuration Change Process](configuration-change-process.md)
- [System Architecture](../architecture.md)

---

_Документ создан в рамках оптимизации конфигураций ERNI-KI 2025-09-25_
