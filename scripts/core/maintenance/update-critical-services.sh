#!/usr/bin/env bash

# Unified critical service upgrade workflow for ERNI-KI
# - Uses docker compose definitions as the source of truth for image tags
# - Creates targeted backups only once per run
# - Restarts dependent services and performs health checks after each upgrade

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/compose.yml"
BACKUP_ROOT="$PROJECT_ROOT/.config-backup/upgrades"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"

DEFAULT_SERVICES=(db redis ollama openwebui litellm nginx)
SELECTED_SERVICES=()
SKIP_BACKUP=false

declare -A SERVICE_DEPENDENTS=(
  [ollama]="openwebui litellm ollama-exporter"
  [db]="openwebui mcposerver backrest"
  [redis]="openwebui"
)

declare -A SERVICE_HEALTHCHECKS=(
  [ollama]='curl -fsS http://localhost:11434/api/tags >/dev/null'
  [openwebui]='curl -fsS http://localhost:8080/health >/dev/null'
  [litellm]='curl -fsS http://localhost:4000/health/liveliness >/dev/null'
  [nginx]='curl -fsS http://localhost/health >/dev/null'
  [db]='docker compose exec -T db pg_isready -U postgres >/dev/null'
  [redis]='docker compose exec -T redis redis-cli ping | grep -q PONG'
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
  printf "${BLUE}[%s]${NC} %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1"
}

success() {
  printf "${GREEN}✅ %s${NC}\n" "$1"
}

warn() {
  printf "${YELLOW}⚠️  %s${NC}\n" "$1"
}

fail() {
  printf "${RED}❌ %s${NC}\n" "$1"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [service ...]

Options:
  -s, --services SERVICE1,SERVICE2   Comma separated services to upgrade
  -n, --no-backup                   Skip backup steps (NOT recommended)
  -l, --list                        Show default critical services
  -h, --help                        Show this help

When no services are specified, the default critical set is: ${DEFAULT_SERVICES[*]}
EOF
}

ensure_environment() {
  if [[ ! -f "$COMPOSE_FILE" ]]; then
    fail "compose.yml не найден. Запустите скрипт из корня репозитория."
    exit 1
  fi

  if ! command -v docker >/dev/null; then
    fail "Docker не установлен."
    exit 1
  fi

  if ! docker compose version >/dev/null 2>&1; then
    fail "Docker Compose V2 недоступен."
    exit 1
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -s|--services)
        IFS=',' read -r -a SELECTED_SERVICES <<< "${2:-}"
        shift 2
        ;;
      -n|--no-backup)
        SKIP_BACKUP=true
        shift
        ;;
      -l|--list)
        echo "Default critical services: ${DEFAULT_SERVICES[*]}"
        exit 0
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        SELECTED_SERVICES+=("$1")
        shift
        ;;
    esac
  done

  if [[ ${#SELECTED_SERVICES[@]} -eq 0 ]]; then
    SELECTED_SERVICES=("${DEFAULT_SERVICES[@]}")
  fi
}

compose() {
  (cd "$PROJECT_ROOT" && docker compose "$@")
}

collect_available_services() {
  mapfile -t AVAILABLE_SERVICES < <(compose config --services)
}

service_exists() {
  local target="$1"
  printf '%s\n' "${AVAILABLE_SERVICES[@]}" | grep -qx "$target"
}

create_backup() {
  local service="$1"
  [[ "$SKIP_BACKUP" == true ]] && return

  mkdir -p "$BACKUP_DIR"

  case "$service" in
    db)
      log "Создание резервной копии PostgreSQL..."
      if compose exec -T db pg_dumpall -U postgres > "$BACKUP_DIR/postgres-$TIMESTAMP.sql" 2>/dev/null; then
        success "PostgreSQL dump сохранён: $BACKUP_DIR/postgres-$TIMESTAMP.sql"
      else
        warn "Не удалось создать dump PostgreSQL. Продолжаем без бэкапа."
      fi
      ;;
    openwebui)
      log "Архивация данных OpenWebUI..."
      if tar -czf "$BACKUP_DIR/openwebui-data.tgz" -C "$PROJECT_ROOT/data" openwebui >/dev/null 2>&1; then
        success "OpenWebUI архив создан: $BACKUP_DIR/openwebui-data.tgz"
      else
        warn "Не удалось архивировать data/openwebui."
      fi
      ;;
    ollama)
      log "Архивация моделей Ollama..."
      compose exec -T ollama ollama list > "$BACKUP_DIR/ollama-models.txt" 2>/dev/null || true
      if tar -czf "$BACKUP_DIR/ollama-data.tgz" -C "$PROJECT_ROOT/data" ollama >/dev/null 2>&1; then
        success "Ollama архив создан: $BACKUP_DIR/ollama-data.tgz"
      else
        warn "Не удалось архивировать data/ollama."
      fi
      ;;
    *)
      ;;
  esac
}

run_health_check() {
  local service="$1"
  local cmd="${SERVICE_HEALTHCHECKS[$service]:-}"

  if [[ -z "$cmd" ]]; then
    log "Health-check для $service не определён, пропускаем."
    return 0
  fi

  log "Проверка здоровья $service..."
  if (cd "$PROJECT_ROOT" && eval "$cmd"); then
    success "$service в состоянии healthy"
    return 0
  else
    fail "$service не прошёл health-check."
    return 1
  fi
}

restart_dependents() {
  local service="$1"
  local deps="${SERVICE_DEPENDENTS[$service]:-}"
  [[ -z "$deps" ]] && return

  log "Перезапуск зависимых сервисов: $deps"
  compose up -d $deps >/dev/null
}

update_service() {
  local service="$1"

  if ! service_exists "$service"; then
    warn "Сервис $service отсутствует в compose.yml — пропускаем."
    return 0
  fi

  log "=== Обновление сервиса $service ==="
  create_backup "$service"

  log "Загрузка новых образов ($service)..."
  compose pull "$service" >/dev/null

  log "Запуск обновлённого сервиса $service..."
  compose up -d "$service" >/dev/null

  restart_dependents "$service"

  if run_health_check "$service"; then
    success "Сервис $service успешно обновлён."
    return 0
  else
    fail "Сервис $service обновлён, но не прошёл проверку."
    return 1
  fi
}

main() {
  ensure_environment
  parse_args "$@"
  collect_available_services

  local failed=()

  for service in "${SELECTED_SERVICES[@]}"; do
    if ! update_service "$service"; then
      failed+=("$service")
    fi
  done

  if [[ ${#failed[@]} -gt 0 ]]; then
    fail "Следующие сервисы требуют внимания: ${failed[*]}"
    exit 1
  fi

  success "Критические сервисы обновлены: ${SELECTED_SERVICES[*]}"
}

main "$@"
