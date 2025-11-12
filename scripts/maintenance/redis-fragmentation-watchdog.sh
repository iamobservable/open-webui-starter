#!/usr/bin/env bash
#
# Redis fragmentation watchdog for ERNI-KI
# Usage: ./scripts/maintenance/redis-fragmentation-watchdog.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

DRY_RUN=false
THRESHOLD="${REDIS_FRAGMENTATION_THRESHOLD:-4.0}"
LOG_FILE="${PROJECT_DIR}/logs/redis-fragmentation-watchdog.log"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --threshold)
      THRESHOLD="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

log() {
  mkdir -p "$(dirname "$LOG_FILE")"
  printf "[%s] %s\n" "$(timestamp)" "$1" | tee -a "$LOG_FILE"
}

info="$(docker compose exec -T redis redis-cli info memory || true)"
if [[ -z "$info" ]]; then
  log "redis-cli info memory failed (is redis running?)"
  exit 1
fi

ratio="$(awk -F':' '/^mem_fragmentation_ratio/ {gsub(/\r/,"", $2); print $2}' <<<"$info")"
ratio="${ratio:-0}"

if awk "BEGIN {exit !($ratio > $THRESHOLD)}"; then
  log "Fragmentation ratio ${ratio} > threshold ${THRESHOLD}"
  if $DRY_RUN; then
    log "Dry-run: skipping redis-cli memory purge"
  else
    if docker compose exec -T redis redis-cli memory purge >/dev/null 2>&1; then
      log "Issued redis-cli memory purge"
    else
      log "Failed to run redis-cli memory purge"
      exit 1
    fi
  fi
else
  log "Fragmentation ratio ${ratio} is within threshold ${THRESHOLD}"
fi
