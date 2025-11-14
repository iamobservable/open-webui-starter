#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="$PROJECT_DIR/data/cron-status"
mkdir -p "$STATE_DIR"

job="${1:?job name is required}"
status="${2:?status is required}"
message="${3:-}"
now="$(date +%s)"
normalized_status="${status,,}"
if [[ "$normalized_status" != "success" && "$normalized_status" != "failure" ]]; then
  echo "Unsupported status '$status'. Use success|failure" >&2
  exit 1
fi
cat >"$STATE_DIR/${job}.status" <<EOFSTATE
timestamp=$now
status=$normalized_status
message=$(echo "$message" | tr '\n' ' ')
EOFSTATE
