#!/bin/bash
# ERNI-KI Cron Setup for Log Rotation
# Настройка автоматической ротации логов через cron

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "⏰ Настройка автоматической ротации логов через cron..."

# Проверка существования скриптов
if [ ! -f "$SCRIPT_DIR/rotate-logs.sh" ]; then
    echo "❌ Скрипт rotate-logs.sh не найден"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/elasticsearch-retention.sh" ]; then
    echo "❌ Скрипт elasticsearch-retention.sh не найден"
    exit 1
fi

# Создание временного файла crontab
TEMP_CRON=$(mktemp)
trap "rm -f $TEMP_CRON" EXIT

# Получение текущего crontab (если есть)
crontab -l 2>/dev/null > "$TEMP_CRON" || true

# Удаление старых записей ERNI-KI (если есть)
sed -i '/# ERNI-KI Log Rotation/d' "$TEMP_CRON"
sed -i '/rotate-logs\.sh/d' "$TEMP_CRON"
sed -i '/elasticsearch-retention\.sh/d' "$TEMP_CRON"

# Добавление новых cron задач
cat >> "$TEMP_CRON" << EOF

# ERNI-KI Log Rotation - Автоматическая ротация логов
# Ежедневная ротация локальных логов в 03:00
0 3 * * * cd "$PROJECT_ROOT" && ./scripts/rotate-logs.sh >> logs/rotation.log 2>&1

# Еженедельная очистка Elasticsearch индексов в воскресенье в 03:30
30 3 * * 0 cd "$PROJECT_ROOT" && ./scripts/elasticsearch-retention.sh full >> logs/elasticsearch-retention.log 2>&1

# Ежедневная оптимизация Elasticsearch в 04:00
0 4 * * * cd "$PROJECT_ROOT" && ./scripts/elasticsearch-retention.sh optimize >> logs/elasticsearch-retention.log 2>&1
EOF

# Установка нового crontab
if crontab "$TEMP_CRON"; then
    echo "✅ Cron задачи установлены успешно"
else
    echo "❌ Ошибка установки cron задач"
    exit 1
fi

# Создание директории для логов ротации
mkdir -p "$PROJECT_ROOT/logs"

# Создание начальных лог файлов
touch "$PROJECT_ROOT/logs/rotation.log"
touch "$PROJECT_ROOT/logs/elasticsearch-retention.log"

echo ""
echo "📋 Установленные cron задачи:"
echo "   🔄 03:00 ежедневно - Ротация локальных логов"
echo "   🗄️  03:30 воскресенье - Полная очистка Elasticsearch"
echo "   ⚡ 04:00 ежедневно - Оптимизация Elasticsearch"
echo ""
echo "📁 Логи ротации:"
echo "   📄 Локальные логи: $PROJECT_ROOT/logs/rotation.log"
echo "   📄 Elasticsearch: $PROJECT_ROOT/logs/elasticsearch-retention.log"
echo ""
echo "🔧 Управление cron:"
echo "   • Просмотр задач: crontab -l"
echo "   • Редактирование: crontab -e"
echo "   • Удаление всех: crontab -r"
echo ""
echo "🧪 Тестирование:"
echo "   • Ручная ротация: ./scripts/rotate-logs.sh"
echo "   • Elasticsearch cleanup: ./scripts/elasticsearch-retention.sh cleanup"
echo ""

# Проверка статуса cron сервиса
if systemctl is-active --quiet cron 2>/dev/null || systemctl is-active --quiet crond 2>/dev/null; then
    echo "✅ Cron сервис активен"
else
    echo "⚠️  Cron сервис может быть неактивен. Проверьте: systemctl status cron"
fi

echo ""
echo "🎉 Настройка автоматической ротации логов завершена!"
