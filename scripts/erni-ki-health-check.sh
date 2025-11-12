#!/usr/bin/env bash

# Historical entry point kept for compatibility. Generates a markdown report.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/health-monitor.sh"

REPORT_FILE="diagnostic-report-$(date '+%Y-%m-%d_%H-%M-%S').md"
REPORT_DIR="$SCRIPT_DIR/../.config-backup/monitoring"
REPORT_PATH="$REPORT_DIR/$REPORT_FILE"

mkdir -p "$REPORT_DIR"

if [[ ! -x "$TARGET" ]]; then
  echo "❌ Не найден scripts/health-monitor.sh" >&2
  exit 1
fi

exec "$TARGET" --report "$REPORT_PATH" "$@"
