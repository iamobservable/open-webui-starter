#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
export PROJECT_DIR
LOG_FILE="$PROJECT_DIR/.config-backup/logs/alertmanager-queue.log"
PROM_URL="${PROMETHEUS_URL:-http://localhost:9091}"
THRESHOLD="${ALERTMANAGER_QUEUE_WARN:-100}"
HARD_LIMIT="${ALERTMANAGER_QUEUE_HARD_LIMIT:-500}"
RUNBOOK_URL="docs/operations/monitoring-guide.md#alertmanagerQueue"
CRON_STATUS_HELPER="$PROJECT_DIR/scripts/monitoring/record-cron-status.sh"
JOB_NAME="alertmanager_queue_watch"
record_status() {
  [[ -x "$CRON_STATUS_HELPER" ]] || return 0
  "$CRON_STATUS_HELPER" "$JOB_NAME" "$1" "$2" || true
}
trap 'record_status failure "queue monitor crashed"' ERR
QUERY='alertmanager_cluster_messages_queued'
export HARD_LIMIT RUNBOOK_URL

mkdir -p "$(dirname "$LOG_FILE")"

response=$(curl -fsS "$PROM_URL/api/v1/query" --data-urlencode "query=$QUERY" || true)
if [[ -z "$response" ]]; then
  printf "[%s] queue-monitor: не удалось получить ответ от %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$PROM_URL" >> "$LOG_FILE"
  record_status failure "prometheus response empty"
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

hard_limit = float(os.environ.get('HARD_LIMIT', '0') or 0)
runbook_url = os.environ.get('RUNBOOK_URL', 'docs/operations/monitoring-guide.md#alertmanagerQueue')
if hard_limit and value > hard_limit:
    with open(log_path, 'a', encoding='utf-8') as fh:
        fh.write(
            f"[{ts}] queue-monitor: value {value} > hard_limit {hard_limit}. Escalate via Alertmanager runbook: {runbook_url}\n"
        )
    sys.exit(2)
PY

status=$?
if (( status == 2 )); then
  record_status failure "queue exceeded hard limit"
  exit 2
fi

record_status success "queue check ok"
