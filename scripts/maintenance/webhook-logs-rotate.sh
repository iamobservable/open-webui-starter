#!/usr/bin/env bash
#
# Очистка и архивирование Alertmanager webhook-логов

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

WEBHOOK_DIR="${PROJECT_DIR}/data/webhook-logs"
ARCHIVE_DIR="${WEBHOOK_DIR}/archive"
RETENTION_DAYS="${WEBHOOK_LOG_RETENTION_DAYS:-7}"
ARCHIVE_RETENTION_DAYS="${WEBHOOK_LOG_ARCHIVE_RETENTION_DAYS:-30}"

mkdir -p "$ARCHIVE_DIR"

log() {
  printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

if [[ ! -d "$WEBHOOK_DIR" ]]; then
  log "Каталог $WEBHOOK_DIR не найден"
  exit 0
fi

cutoff_epochs=$(date -d "-${RETENTION_DAYS} days" +%s)

# Группируем файлы по дате из имени (alert_<severity>_YYYYMMDD_HHMMSS.json)
find "$WEBHOOK_DIR" -maxdepth 1 -type f -name 'alert_*.json' -print0 | while IFS= read -r -d '' file; do
  base="$(basename "$file")"
  IFS='_' read -r prefix severity date_part time_part rest <<<"$base"
  [[ -z "${date_part:-}" || "${#date_part}" -ne 8 ]] && continue
  if ! file_epoch=$(date -d "$date_part" +%s 2>/dev/null); then
    continue
  fi
  if (( file_epoch > cutoff_epochs )); then
    continue
  fi
  bucket="${ARCHIVE_DIR}/${date_part}"
  mkdir -p "$bucket"
  mv "$file" "$bucket/" 2>/dev/null || true
done

# Упаковываем каталоги по датам и удаляем исходные файлы
shopt -s nullglob
for day_dir in "${ARCHIVE_DIR}"/*; do
  [[ -d "$day_dir" ]] || continue
  day="$(basename "$day_dir")"
  archive_file="${ARCHIVE_DIR}/alert-${day}.tar.gz"
  if [[ -n "$(ls -A "$day_dir")" ]]; then
    tar -czf "$archive_file" -C "$day_dir" . && rm -rf "$day_dir"
    log "Заархивированы вебхуки за ${day} → $(basename "$archive_file")"
  else
    rmdir "$day_dir"
  fi
done
shopt -u nullglob

# Удаляем старые архивы
find "$ARCHIVE_DIR" -maxdepth 1 -type f -name 'alert-*.tar.gz' -mtime +"$ARCHIVE_RETENTION_DAYS" -print -delete

log "Очистка завершена"
