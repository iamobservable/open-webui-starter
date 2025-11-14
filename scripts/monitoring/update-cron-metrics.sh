#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="$PROJECT_DIR/data/cron-status"
TEXTFILE_DIR="${TEXTFILE_DIR:-$PROJECT_DIR/data/node-exporter-textfile}"
METRIC_FILE="$TEXTFILE_DIR/cron_watchdogs.prom"
mkdir -p "$STATE_DIR" "$TEXTFILE_DIR"

# job=>SLA seconds mapping
declare -A SLA
SLA[logging_reports_daily]=$((24 * 60 * 60 + 6 * 60 * 60))   # 30h
SLA[logging_reports_weekly]=$((8 * 24 * 60 * 60))            # 8 days
SLA[redis_fragmentation_watchdog]=$((15 * 60))               # 15 minutes
SLA[alertmanager_queue_watch]=$((10 * 60))                   # 10 minutes

now=$(date +%s)
tmp_file="${METRIC_FILE}.tmp"
: >"$tmp_file"

for job in "${!SLA[@]}"; do
  state_file="$STATE_DIR/${job}.status"
  last_ts=0
  success=0
  if [[ -f "$state_file" ]]; then
    # shellcheck disable=SC1090
    source "$state_file"
    last_ts="${timestamp:-0}"
    if [[ "${status:-failure}" == "success" ]]; then
      success=1
    fi
  fi
  age=$(( now - last_ts ))
  if (( age < 0 )); then
    age=0
  fi
  sla="${SLA[$job]}"
  printf 'erni_cron_job_success{job="%s"} %s
' "$job" "$success" >>"$tmp_file"
  printf 'erni_cron_job_age_seconds{job="%s"} %s
' "$job" "$age" >>"$tmp_file"
  printf 'erni_cron_job_sla_seconds{job="%s"} %s
' "$job" "$sla" >>"$tmp_file"
  printf 'erni_cron_job_last_run_timestamp{job="%s"} %s
' "$job" "$last_ts" >>"$tmp_file"
done

mv "$tmp_file" "$METRIC_FILE"
