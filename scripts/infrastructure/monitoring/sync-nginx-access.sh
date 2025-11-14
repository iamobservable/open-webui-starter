#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TARGET_DIR="${NGINX_SYNC_TARGET:-$PROJECT_ROOT/data/nginx/logs}"
LOG_FILE="${PROJECT_ROOT}/logs/nginx-access-sync.log"
TMP_FILE="${TARGET_DIR}/access.log.tmp"
FINAL_FILE="${TARGET_DIR}/access.log"

mkdir -p "$TARGET_DIR" "${PROJECT_ROOT}/logs"

log() {
  printf '[%s] %s\n' "$(date -Iseconds)" "$1" | tee -a "$LOG_FILE"
}

if ! command -v docker >/dev/null 2>&1; then
  log "docker command not available"
  exit 1
fi

log "Copying nginx access log from container"
if docker compose -f "$PROJECT_ROOT/compose.yml" cp nginx:/var/log/nginx/access.log "$TMP_FILE" >/dev/null 2>&1; then
  mv "$TMP_FILE" "$FINAL_FILE"
  chmod 640 "$FINAL_FILE"
  log "Updated $FINAL_FILE"
else
  log "Failed to copy access log from nginx"
  exit 1
fi
