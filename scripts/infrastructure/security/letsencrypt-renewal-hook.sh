#!/bin/bash
# Hook скрипт для перезагрузки nginx после обновления Let's Encrypt сертификата

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LOG_FILE="$PROJECT_ROOT/logs/ssl-renewal-$(date +%Y%m%d).log"

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Certificate renewal hook executed" >> "$LOG_FILE"

cd "$PROJECT_ROOT"

# Перезагрузка nginx
if docker compose exec -T nginx nginx -s reload 2>> "$LOG_FILE"; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Nginx reloaded successfully" >> "$LOG_FILE"
else
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Nginx reload failed, restarting container" >> "$LOG_FILE"
    docker compose restart nginx >> "$LOG_FILE" 2>&1
fi

# Перезагрузка Cloudflare Tunnel
docker compose restart cloudflared >> "$LOG_FILE" 2>&1

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Certificate renewal completed" >> "$LOG_FILE"
