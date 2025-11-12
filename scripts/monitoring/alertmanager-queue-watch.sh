#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="$PROJECT_DIR/.config-backup/logs/alertmanager-queue.log"
PROM_URL="${PROMETHEUS_URL:-http://localhost:9091}"
THRESHOLD="${ALERTMANAGER_QUEUE_WARN:-100}"
QUERY='alertmanager_cluster_messages_queued'

mkdir -p "$(dirname "$LOG_FILE")"

response=$(curl -fsS "$PROM_URL/api/v1/query" --data-urlencode "query=$QUERY" || true)
if [[ -z "$response" ]]; then
  printf "[%s] queue-monitor: не удалось получить ответ от %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$PROM_URL" >> "$LOG_FILE"
  exit 0
fi

ALERT_RESPONSE="$response" python3 - "$LOG_FILE" "$THRESHOLD" <<'PY'
import json
import sys
import os
from datetime import datetime

log_path = sys.argv[1]
threshold = float(sys.argv[2])
ts = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
try:
    payload = json.loads(os.environ.get('ALERT_RESPONSE', ''))
except json.JSONDecodeError:
    with open(log_path, 'a', encoding='utf-8') as fh:
        fh.write(f"[{ts}] queue-monitor: некорректный JSON от Prometheus\n")
    sys.exit(0)

value = 0.0
try:
    result = payload['data']['result'][0]
    value = float(result['value'][1])
except (KeyError, IndexError, ValueError):
    pass

status = 'OK' if value <= threshold else 'WARN'
with open(log_path, 'a', encoding='utf-8') as fh:
    fh.write(f"[{ts}] queue-monitor: {value} (threshold={threshold}) status={status}\n")
PY
