#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[openwebui-entrypoint] $*" >&2
}

read_secret() {
  local secret_name="$1"
  local secret_file="/run/secrets/${secret_name}"

  if [[ -f "${secret_file}" ]]; then
    # Strip trailing newline without using subshells repeatedly
    tr -d '\r' <"${secret_file}" | tr -d '\n'
    return 0
  fi

  return 1
}

configure_postgres_urls() {
  local password
  if ! password="$(read_secret "postgres_password")"; then
    log "warning: postgres_password secret is not available; DATABASE_URL will remain unchanged"
    return
  fi

  local db_user="${OPENWEBUI_DB_USER:-postgres}"
  local db_name="${OPENWEBUI_DB_NAME:-openwebui}"
  local db_host="${OPENWEBUI_DB_HOST:-db}"
  local db_port="${OPENWEBUI_DB_PORT:-5432}"

  local url="postgresql://${db_user}:${password}@${db_host}:${db_port}/${db_name}"

  if [[ -z "${DATABASE_URL:-}" ]]; then
    export DATABASE_URL="${url}"
  fi

  if [[ -z "${PGVECTOR_DB_URL:-}" ]]; then
    export PGVECTOR_DB_URL="${url}"
  fi
}

configure_webui_secret() {
  local secret_key
  if secret_key="$(read_secret "openwebui_secret_key")"; then
    export WEBUI_SECRET_KEY="${secret_key}"
  else
    log "warning: openwebui_secret_key secret missing; WEBUI_SECRET_KEY is not set"
  fi
}

configure_openai_keys() {
  local api_key
  if ! api_key="$(read_secret "litellm_api_key")"; then
    log "warning: litellm_api_key secret missing; OpenAI-related keys remain unchanged"
    return
  fi

  export OPENAI_API_KEY="${OPENAI_API_KEY:-$api_key}"
  export LITELLM_API_KEY="${LITELLM_API_KEY:-$api_key}"
  export AUDIO_STT_OPENAI_API_KEY="${AUDIO_STT_OPENAI_API_KEY:-$api_key}"
}

main() {
  configure_postgres_urls
  configure_webui_secret
  configure_openai_keys

  if [[ $# -gt 0 ]]; then
    exec "$@"
  fi

  if [[ -x "/app/backend/start.sh" ]]; then
    exec /bin/bash /app/backend/start.sh
  fi

  log "falling back to uvicorn main module"
  exec python3 -m open_webui.main
}

main "$@"
