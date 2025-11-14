#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DB_DIR="${FLUENTBIT_DB_DIR:-$PROJECT_ROOT/data/fluent-bit/db}"
LOG_FILE="$PROJECT_ROOT/logs/fluentbit-db-monitor.log"
WARN_GB=${FLUENTBIT_DB_WARN_GB:-5}
CRIT_GB=${FLUENTBIT_DB_CRIT_GB:-8}

mkdir -p "$(dirname "$LOG_FILE")"

log() {
  printf '[%s] %s\n' "$(date -Iseconds)" "$1" | tee -a "$LOG_FILE"
}

if [[ ! -d "$DB_DIR" ]]; then
  log "Directory $DB_DIR not found"
  exit 0
fi

SIZE_KB=$(du -sk "$DB_DIR" | awk '{print $1}')
SIZE_GB=$(awk -v kb="$SIZE_KB" 'BEGIN {printf "%.2f", kb/1048576}')

log "Fluent Bit DB size: ${SIZE_GB}GB"

compare() {
  local value=$1 threshold=$2
  awk -v v="$value" -v t="$threshold" 'BEGIN {exit !(v>t)}'
}

status=0
if compare "$SIZE_GB" "$WARN_GB"; then
  log "WARNING: Fluent Bit DB exceeded ${WARN_GB}GB"
  status=1
fi
if compare "$SIZE_GB" "$CRIT_GB"; then
  log "CRITICAL: Fluent Bit DB exceeded ${CRIT_GB}GB -- consider cleanup"
  status=2
fi
exit $status
