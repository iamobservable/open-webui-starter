#!/bin/bash

# ERNI-KI Rate Limiting Dashboard
# Простой dashboard для мониторинга rate limiting

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="$PROJECT_ROOT/logs/rate-limiting-state.json"

clear
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                        ERNI-KI Rate Limiting Dashboard                      ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo

# Текущий статус
echo "📊 Текущий статус:"
if [[ -f "$STATE_FILE" ]]; then
    echo "   Последнее обновление: $(jq -r '.timestamp' "$STATE_FILE" 2>/dev/null || echo 'N/A')"
    echo "   Блокировок за минуту: $(jq -r '.total_blocks' "$STATE_FILE" 2>/dev/null || echo 'N/A')"
    echo "   Максимальное превышение: $(jq -r '.max_excess' "$STATE_FILE" 2>/dev/null || echo 'N/A')"
else
    echo "   ⚠️  Нет данных мониторинга"
fi

echo

# Статистика по зонам
echo "🎯 Статистика по зонам:"
if [[ -f "$STATE_FILE" ]] && jq -e '.zones | length > 0' "$STATE_FILE" >/dev/null 2>&1; then
    jq -r '.zones[] | "   \(.zone): \(.count) блокировок"' "$STATE_FILE" 2>/dev/null
else
    echo "   ✅ Нет блокировок"
fi

echo

# Топ IP адресов
echo "🌐 Топ IP адресов:"
if [[ -f "$STATE_FILE" ]] && jq -e '.top_ips | length > 0' "$STATE_FILE" >/dev/null 2>&1; then
    jq -r '.top_ips[] | "   \(.ip): \(.count) блокировок"' "$STATE_FILE" 2>/dev/null | head -5
else
    echo "   ✅ Нет проблемных IP"
fi

echo

# Последние алерты
echo "🚨 Последние алерты:"
local alert_file="$PROJECT_ROOT/logs/rate-limiting-alerts.log"
if [[ -f "$alert_file" ]]; then
    tail -5 "$alert_file" | grep -E "^\[.*\] \[.*\]" | while read -r line; do
        echo "   $line"
    done
else
    echo "   ✅ Нет алертов"
fi

echo
echo "Обновлено: $(date)"
echo "Для выхода нажмите Ctrl+C"
