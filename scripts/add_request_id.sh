#!/bin/bash

# Скрипт для добавления X-Request-ID header во все proxy_set_header блоки nginx
# Фаза 2 оптимизации логгирования ERNI-KI

CONFIG_FILE="conf/nginx/conf.d/default.conf"
BACKUP_FILE=".config-backup/logging-optimization-20250822-162618/default.conf.before-request-id"

echo "=== Добавление X-Request-ID header в nginx конфигурацию ==="

# Создаем дополнительный backup
cp "$CONFIG_FILE" "$BACKUP_FILE"

# Добавляем X-Request-ID header после каждого proxy_set_header X-Forwarded-Proto $scheme;
# но только если X-Request-ID еще не добавлен
sed -i '/proxy_set_header X-Forwarded-Proto \$scheme;/a\    proxy_set_header X-Request-ID $final_request_id;' "$CONFIG_FILE"

# Удаляем дублирующиеся строки X-Request-ID (если они уже были)
sed -i '/proxy_set_header X-Request-ID \$final_request_id;/{N;/\n.*proxy_set_header X-Request-ID \$final_request_id;/d;}' "$CONFIG_FILE"

echo "✅ X-Request-ID header добавлен во все proxy блоки"
echo "📁 Backup создан: $BACKUP_FILE"

# Проверяем количество добавленных заголовков
COUNT=$(grep -c "proxy_set_header X-Request-ID" "$CONFIG_FILE")
echo "📊 Добавлено X-Request-ID headers: $COUNT"

# Проверяем синтаксис nginx
echo "🔍 Проверка синтаксиса nginx..."
docker-compose exec nginx nginx -t 2>/dev/null || echo "⚠️  Nginx не запущен, проверка синтаксиса пропущена"

echo "✅ Скрипт завершен успешно"
