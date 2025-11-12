#!/usr/bin/env bash

# Wrapper around the unified health monitor.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TARGET="$PROJECT_ROOT/scripts/health-monitor.sh"

if [[ ! -x "$TARGET" ]]; then
  echo "❌ Не найден scripts/health-monitor.sh" >&2
  exit 1
fi

exec "$TARGET" "$@"
