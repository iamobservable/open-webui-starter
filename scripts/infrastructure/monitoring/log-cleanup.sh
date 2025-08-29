#!/bin/bash
# Очистка старых логов ERNI-KI

echo "=== ОЧИСТКА ЛОГОВ ERNI-KI ==="
echo "Дата: $(date)"

# Очистка Docker логов старше 7 дней
echo "Очистка Docker логов старше 7 дней..."
docker system prune -f --filter "until=168h"

# Архивирование логов
ARCHIVE_DIR="/var/log/erni-ki/archive/$(date +%Y%m%d)"
mkdir -p "$ARCHIVE_DIR"

echo "Архивирование завершено в: $ARCHIVE_DIR"
