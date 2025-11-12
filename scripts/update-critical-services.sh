#!/usr/bin/env bash

# Backwards-compatible wrapper. The real implementation lives under
# scripts/core/maintenance/update-critical-services.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/core/maintenance/update-critical-services.sh"

if [[ ! -x "$TARGET" ]]; then
  echo "❌ Не найден основной скрипт обновления: $TARGET" >&2
  exit 1
fi

exec "$TARGET" "$@"
