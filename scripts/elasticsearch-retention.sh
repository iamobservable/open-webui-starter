#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ES_URL="${ES_URL:-http://localhost:9200}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
INDEX_PATTERNS=("logs-" ".monitoring-" "monitoring-")

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

ensure_es_accessible() {
  if ! curl -sSf "$ES_URL" >/dev/null; then
    echo "❌ Elasticsearch not reachable at $ES_URL"
    exit 1
  fi
}

collect_candidates() {
  local threshold_sec=$(( $(date +%s) - RETENTION_DAYS * 86400 ))
  local threshold_ms=$(( threshold_sec * 1000 ))
  local index
  local created
  local matches=()

  while read -r index created; do
    [[ -z "$index" || -z "$created" ]] && continue
    [[ ! "$created" =~ ^[0-9]+$ ]] && continue
    for prefix in "${INDEX_PATTERNS[@]}"; do
      if [[ "$index" == "$prefix"* ]] && (( created < threshold_ms )); then
        matches+=("$index")
        break
      fi
    done
  done < <(curl -sS "$ES_URL/_cat/indices?h=index,creation.date" | tr -s ' ')

  printf '%s\n' "${matches[@]}"
}

delete_indices() {
  local idx="$1"
  idx="$(echo -n "$idx" | tr -d '\r')"
  if [[ -z "$idx" ]]; then
    return
  fi
  log "Удаляю индекс $idx"
  if curl -sSf -X DELETE "$ES_URL/$idx" >/dev/null; then
    log "Удаление $idx: ok"
  else
    log "⚠️  Не удалось удалить $idx"
  fi
}

force_merge() {
  log "Запуск _forcemerge (макс. сегменты = 1)"
  curl -sSf -X POST "$ES_URL/_forcemerge?max_num_segments=1&only_expunge_deletes=true" >/dev/null
  log "Форсимерж завершён"
}

case "${1:-status}" in
  full)
    log "Полная очистка Elasticsearch (индексы старше ${RETENTION_DAYS} дней)"
    ensure_es_accessible
    mapfile -t candidates < <(collect_candidates)
    if [[ "${#candidates[@]}" -eq 0 ]]; then
      log "Нет индекс-совых для удаления"
      exit 0
    fi

    for idx in "${candidates[@]}"; do
      delete_indices "$idx"
    done
    ;;

  optimize)
    log "Ежедневная оптимизация Elasticsearch"
    ensure_es_accessible
    force_merge
    ;;

  cleanup)
    log "Выполнение ретеншн cleanup (синтаксический алиас)"
    "$0" full
    ;;

  status)
    log "Проверка статуса Elasticsearch"
    if curl -sSf "$ES_URL/_cluster/health" | tee /dev/null >/dev/null; then
      log "Elasticsearch доступен"
    else
      log "Elasticsearch недоступен"
      exit 1
    fi
    ;;

  *)
    echo "Usage: $0 {full|optimize|cleanup|status}"
    exit 1
    ;;
esac
