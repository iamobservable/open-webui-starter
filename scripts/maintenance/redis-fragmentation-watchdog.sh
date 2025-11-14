#!/usr/bin/env bash
#
# Redis fragmentation watchdog for ERNI-KI
# Usage: ./scripts/maintenance/redis-fragmentation-watchdog.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_DIR нужно указывать на корень репозитория, иначе docker compose
# выполняется из каталога scripts и не находит compose.yml.
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR"

DRY_RUN=false
THRESHOLD="${REDIS_FRAGMENTATION_THRESHOLD:-4.0}"
LOG_FILE="${PROJECT_DIR}/logs/redis-fragmentation-watchdog.log"
STATE_FILE="${PROJECT_DIR}/logs/redis-fragmentation-watchdog.state"
COOLDOWN="${REDIS_FRAGMENTATION_COOLDOWN_SECONDS:-600}"
MAX_PURGES="${REDIS_FRAGMENTATION_MAX_PURGES:-6}"

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
used="$(awk -F':' '/^used_memory:/ {gsub(/\r/,"", $2); print $2}' <<<"$info")"
rss="$(awk -F':' '/^used_memory_rss:/ {gsub(/\r/,"", $2); print $2}' <<<"$info")"
peak="$(awk -F':' '/^used_memory_peak:/ {gsub(/\r/,"", $2); print $2}' <<<"$info")"

load_state() {
  [[ -f "$STATE_FILE" ]] || return
  # shellcheck disable=SC1090
  source "$STATE_FILE"
}

persist_state() {
  cat >"$STATE_FILE" <<EOF
LAST_ACTION_TS=$1
RUNS=$2
EOF
}

reset_state() {
  rm -f "$STATE_FILE"
}

load_state
LAST_ACTION_TS="${LAST_ACTION_TS:-0}"
RUNS="${RUNS:-0}"
now="$(date +%s)"

if awk "BEGIN {exit !($ratio > $THRESHOLD)}"; then
  log "Fragmentation ratio ${ratio} > threshold ${THRESHOLD} (used=${used:-0} rss=${rss:-0} peak=${peak:-0})"

  if (( now - LAST_ACTION_TS < COOLDOWN )); then
    log "Previous purge executed $((now - LAST_ACTION_TS))s ago (<${COOLDOWN}s). Skipping duplicate action."
  else
    if $DRY_RUN; then
      log "Dry-run: skipping redis-cli memory purge"
    else
      if docker compose exec -T redis redis-cli memory purge >/dev/null 2>&1; then
        log "Issued redis-cli memory purge"
      else
        log "Failed to run redis-cli memory purge"
        exit 1
      fi

      docker compose exec -T redis redis-cli config set activedefrag yes >/dev/null 2>&1 || true
      docker compose exec -T redis redis-cli config set active-defrag-cycle-max 85 >/dev/null 2>&1 || true
      docker compose exec -T redis redis-cli config rewrite >/dev/null 2>&1 || true

      LAST_ACTION_TS="$now"
      RUNS=$((RUNS + 1))
      persist_state "$LAST_ACTION_TS" "$RUNS"

      if (( RUNS >= MAX_PURGES )); then
        log "Fragmentation persists after $RUNS purges, restarting redis container"
        docker compose restart redis >/dev/null 2>&1 || log "WARN: redis restart failed"
        RUNS=0
        persist_state "$now" "$RUNS"
      fi
    fi
  fi
else
  log "Fragmentation ratio ${ratio} is within threshold ${THRESHOLD}"
  reset_state
fi
