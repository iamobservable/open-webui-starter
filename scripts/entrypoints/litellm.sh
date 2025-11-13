#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[litellm-entrypoint] $*" >&2
}

read_secret() {
  local secret_name="$1"
  local secret_file="/run/secrets/${secret_name}"

  if [[ -f "${secret_file}" ]]; then
    tr -d '\r' <"${secret_file}" | tr -d '\n'
    return 0
  fi

  return 1
}

configure_database_url() {
  local password
  if ! password="$(read_secret "litellm_db_password")"; then
    log "warning: litellm_db_password secret missing; DATABASE_URL will stay unchanged"
    return
  fi

  local db_user="${LITELLM_DB_USER:-litellm_user}"
  local db_name="${LITELLM_DB_NAME:-litellm}"
  local db_host="${LITELLM_DB_HOST:-db}"
  local db_port="${LITELLM_DB_PORT:-5432}"
  local ssl_mode="${LITELLM_DB_SSL_MODE:-disable}"

  local url="postgresql://${db_user}:${password}@${db_host}:${db_port}/${db_name}?sslmode=${ssl_mode}"
  export DATABASE_URL="${DATABASE_URL:-$url}"
}

configure_master_and_salt_keys() {
  local master_key salt_key

  if master_key="$(read_secret "litellm_master_key")"; then
    export LITELLM_MASTER_KEY="${master_key}"
  else
    log "warning: litellm_master_key secret missing; LITELLM_MASTER_KEY is not set"
  fi

  if salt_key="$(read_secret "litellm_salt_key")"; then
    export LITELLM_SALT_KEY="${salt_key}"
  else
    log "warning: litellm_salt_key secret missing; LITELLM_SALT_KEY is not set"
  fi
}

configure_ui_credentials() {
  local ui_password
  if ui_password="$(read_secret "litellm_ui_password")"; then
    export UI_PASSWORD="${ui_password}"
  else
    log "warning: litellm_ui_password secret missing; UI_PASSWORD is unchanged"
  fi
}

configure_api_key() {
  local api_key
  if api_key="$(read_secret "litellm_api_key")"; then
    export LITELLM_API_KEY="${api_key}"
  else
    log "warning: litellm_api_key secret missing; LITELLM_API_KEY remains unchanged"
  fi
}

configure_openai_credentials() {
  local openai_key
  if openai_key="$(read_secret "openai_api_key")"; then
    export OPENAI_API_KEY="${OPENAI_API_KEY:-$openai_key}"
  else
    log "warning: openai_api_key secret missing; OPENAI_API_KEY is unchanged"
  fi
}

configure_publicai_credentials() {
  local publicai_key
  if publicai_key="$(read_secret "publicai_api_key")"; then
    export PUBLICAI_API_KEY="${PUBLICAI_API_KEY:-$publicai_key}"
  else
    log "warning: publicai_api_key secret missing; PUBLICAI_API_KEY is unchanged"
  fi
}

configure_redis_url() {
  local host="${LITELLM_REDIS_HOST:-redis}"
  local port="${LITELLM_REDIS_PORT:-6379}"
  local db="${LITELLM_REDIS_DB:-1}"
  local password

  if password="$(read_secret "redis_password")"; then
    export REDIS_PASSWORD="${REDIS_PASSWORD:-$password}"
    export REDIS_URL="${REDIS_URL:-redis://:${password}@${host}:${port}/${db}}"
    return
  fi

  # Redis auth disabled
  export REDIS_URL="${REDIS_URL:-redis://${host}:${port}/${db}}"
}

prepare_publicai_metrics_dir() {
  local metrics_dir="${LITELLM_PUBLICAI_METRICS_DIR:-/tmp/litellm-publicai-prom}"
  rm -rf "${metrics_dir}"
  mkdir -p "${metrics_dir}"
  chmod 700 "${metrics_dir}"
  export LITELLM_PUBLICAI_METRICS_DIR="${metrics_dir}"
  export PROMETHEUS_MULTIPROC_DIR="${metrics_dir}"
}

main() {
  prepare_publicai_metrics_dir
  configure_database_url
  configure_master_and_salt_keys
  configure_ui_credentials
  configure_api_key
  configure_openai_credentials
  configure_publicai_credentials
  configure_redis_url

  if [[ $# -gt 0 ]]; then
    exec litellm "$@"
  fi

  exec litellm
}

main "$@"
