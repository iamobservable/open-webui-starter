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

OWNER="${DOC_SHARED_OWNER:-}"
GROUP="${DOC_SHARED_GROUP:-}"
PERMS="${DOC_SHARED_PERMS:-770}"
SUDO_HELPER="${DOC_SHARED_USE_SUDO:-true}"

ensure_dir() {
  local dir="$1"

  if [[ -d "$dir" ]]; then
    ensure_perms "$dir"
    return
  fi

  if mkdir -p "$dir" >/dev/null 2>&1; then
    :
  elif [[ "$SUDO_HELPER" == "true" && $(command -v sudo) ]]; then
    if sudo mkdir -p "$dir"; then
      log "Created $dir via sudo"
    else
      log "ERROR: sudo mkdir -p $dir failed"
      exit 1
    fi
  else
    log "ERROR: cannot create $dir (permission denied)"
    exit 1
  fi

  ensure_perms "$dir"
}

ensure_perms() {
  local dir="$1"
  if [[ -n "$OWNER" || -n "$GROUP" ]]; then
    local owner="${OWNER:-}"
    local group="${GROUP:-}"
    local target="$owner"
    [[ -n "$group" ]] && target="${target}:$group"

    if ! chown "$target" "$dir" >/dev/null 2>&1; then
      if [[ "$SUDO_HELPER" == "true" && $(command -v sudo) ]]; then
        sudo chown "$target" "$dir" || log "WARN: sudo chown failed for $dir"
      else
        log "WARN: cannot chown $dir to $target"
      fi
    fi
  fi

  chmod "$PERMS" "$dir" >/dev/null 2>&1 || log "WARN: cannot chmod $PERMS on $dir"
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

if TOTAL_KB=$(du -sk "$ROOT" 2>/dev/null | awk '{print $1}')
then
  TOTAL_GB=$(awk -v kb="$TOTAL_KB" 'BEGIN {printf "%.2f", kb/1048576}')
else
  TOTAL_GB="unknown"
fi
MAX_GB="${DOC_SHARED_MAX_SIZE_GB:-20}"

if [[ "$TOTAL_GB" != "unknown" ]]; then
  exceed=$(awk -v total="$TOTAL_GB" -v max="$MAX_GB" 'BEGIN {print (total > max) ? 1 : 0}')
  if [[ "$exceed" -eq 1 ]]; then
    log "WARNING: shared volume size ${TOTAL_GB}GB exceeds soft limit ${MAX_GB}GB"
  fi
else
  log "WARNING: unable to determine shared volume size (du failed)"
fi
