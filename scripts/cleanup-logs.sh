#!/usr/bin/env bash

# Compatibility wrapper so existing cron jobs reuse the maintained rotation manager.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANAGER="$SCRIPT_DIR/core/maintenance/log-rotation-manager.sh"

if [[ ! -x "$MANAGER" ]]; then
  echo "❌ Не найден основной менеджер ротации логов: $MANAGER" >&2
  exit 1
fi

exec "$MANAGER" "$@"
