#!/usr/bin/env bash
set -euo pipefail

ROOT="${DOC_SHARED_ROOT:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/data/docling/shared}"
MODE="dry-run"

if [[ "${1:-}" == "--apply" ]]; then
  MODE="apply"
  shift
fi

log() {
  printf '[%s] %s\n' "$(date -Iseconds)" "$*"
}

ensure_dir() {
  local dir="$1"
  [[ -d "$dir" ]] || mkdir -p "$dir"
}

cleanup_bucket() {
  local path="$1"
  local days="$2"
  local label="$3"

  [[ -d "$path" ]] || return 0

  log "Checking $label ($path), retention ${days}d, mode=${MODE}"

  if [[ "$MODE" == "apply" ]]; then
    find "$path" -type f -mtime +"$days" -print -delete
    find "$path" -type d -empty -mtime +"$days" -print -delete
  else
    find "$path" -type f -mtime +"$days" -print
  fi
}

ensure_dir "$ROOT/uploads"
ensure_dir "$ROOT/processed"
ensure_dir "$ROOT/exports"
ensure_dir "$ROOT/quarantine"
ensure_dir "$ROOT/tmp"

INPUT_RETENTION="${DOC_SHARED_INPUT_RETENTION_DAYS:-2}"
PROCESSED_RETENTION="${DOC_SHARED_PROCESSED_RETENTION_DAYS:-14}"
EXPORT_RETENTION="${DOC_SHARED_EXPORT_RETENTION_DAYS:-30}"
QUARANTINE_RETENTION="${DOC_SHARED_QUARANTINE_RETENTION_DAYS:-60}"
TMP_RETENTION="${DOC_SHARED_TMP_RETENTION_DAYS:-1}"

cleanup_bucket "$ROOT/uploads" "$INPUT_RETENTION" "raw uploads"
cleanup_bucket "$ROOT/processed" "$PROCESSED_RETENTION" "processed artifacts"
cleanup_bucket "$ROOT/exports" "$EXPORT_RETENTION" "exports"
cleanup_bucket "$ROOT/quarantine" "$QUARANTINE_RETENTION" "quarantine"
cleanup_bucket "$ROOT/tmp" "$TMP_RETENTION" "tmp"

TOTAL_GB=$(du -sg "$ROOT" | awk '{print $1}')
MAX_GB="${DOC_SHARED_MAX_SIZE_GB:-20}"

if (( TOTAL_GB > MAX_GB )); then
  log "WARNING: shared volume size ${TOTAL_GB}GB exceeds soft limit ${MAX_GB}GB"
fi
