#!/bin/bash
# ERNI-KI Manual Log Rotation Script
# Ручная ротация логов с 7-дневным retention

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DATE=$(date +%Y%m%d-%H%M%S)

echo "🔄 Ротация логов ERNI-KI - $(date)"

# Функция ротации логов
rotate_logs() {
    local log_dir="$1"
    local retention_days="$2"
    local description="$3"

    if [ ! -d "$log_dir" ]; then
        echo "📁 Создание директории: $log_dir"
        mkdir -p "$log_dir"
        return
    fi

    echo "🔄 Ротация $description в $log_dir"

    # Найти и сжать логи старше 1 дня
    find "$log_dir" -name "*.log" -type f -mtime +0 -exec gzip {} \; 2>/dev/null || true

    # Удалить сжатые логи старше retention_days дней
    find "$log_dir" -name "*.log.gz" -type f -mtime +$retention_days -delete 2>/dev/null || true

    # Подсчет файлов
    local log_count=$(find "$log_dir" -name "*.log" -type f | wc -l)
    local gz_count=$(find "$log_dir" -name "*.log.gz" -type f | wc -l)

    echo "   📊 Активных логов: $log_count, архивных: $gz_count"
}

# Ротация основных логов (7 дней)
rotate_logs "$PROJECT_ROOT/logs" 7 "основных логов"

# Ротация логов бэкапов (7 дней)
rotate_logs "$PROJECT_ROOT/.config-backup/logs" 7 "логов бэкапов"

# Ротация критических логов (30 дней)
rotate_logs "$PROJECT_ROOT/monitoring/logs/critical" 30 "критических логов"

# Очистка больших Fluent Bit DB файлов
echo "🗄️  Очистка Fluent Bit database файлов..."
if [ -d "$PROJECT_ROOT/data/fluent-bit/db" ]; then
    # Найти WAL файлы больше 50MB и создать их резервные копии
    find "$PROJECT_ROOT/data/fluent-bit/db" -name "*.db-wal" -size +50M -exec cp {} {}.backup-$DATE \; 2>/dev/null || true
    find "$PROJECT_ROOT/data/fluent-bit/db" -name "*.db-wal" -size +50M -exec truncate -s 0 {} \; 2>/dev/null || true

    # Сжать старые backup файлы
    find "$PROJECT_ROOT/data/fluent-bit/db" -name "*.backup-*" -mtime +1 -exec gzip {} \; 2>/dev/null || true
    find "$PROJECT_ROOT/data/fluent-bit/db" -name "*.backup-*.gz" -mtime +7 -delete 2>/dev/null || true
fi

# Статистика дискового пространства
echo ""
echo "💾 Статистика использования дискового пространства:"
echo "   📁 Основные логи: $(du -sh "$PROJECT_ROOT/logs" 2>/dev/null | cut -f1 || echo "0B")"
echo "   📁 Логи бэкапов: $(du -sh "$PROJECT_ROOT/.config-backup/logs" 2>/dev/null | cut -f1 || echo "0B")"
echo "   📁 Критические логи: $(du -sh "$PROJECT_ROOT/monitoring/logs/critical" 2>/dev/null | cut -f1 || echo "0B")"
if [ -d "$PROJECT_ROOT/data/fluent-bit/db" ]; then
    echo "   📁 Fluent Bit DB: $(du -sh "$PROJECT_ROOT/data/fluent-bit/db" 2>/dev/null | cut -f1 || echo "0B")"
else
    echo "   📁 Fluent Bit DB: N/A (директория отсутствует)"
fi

# Проверка свободного места
echo ""
echo "💿 Свободное место на диске:"
df -h "$PROJECT_ROOT" | tail -1 | awk '{print "   🖥️  Использовано: " $3 " из " $2 " (" $5 "), свободно: " $4}'

echo ""
echo "✅ Ротация логов завершена - $(date)"
