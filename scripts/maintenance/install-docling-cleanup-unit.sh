#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
ENV_TARGET="$HOME/.config/docling-cleanup.env"

echo "🛠️  Installing Docling cleanup systemd unit into ${SYSTEMD_USER_DIR}"
mkdir -p "$SYSTEMD_USER_DIR"

install -m 644 "${REPO_ROOT}/ops/systemd/docling-cleanup.service" "$SYSTEMD_USER_DIR/"
install -m 644 "${REPO_ROOT}/ops/systemd/docling-cleanup.timer" "$SYSTEMD_USER_DIR/"

if [[ ! -f "$ENV_TARGET" ]]; then
  mkdir -p "$(dirname "$ENV_TARGET")"
  install -m 600 "${REPO_ROOT}/ops/systemd/docling-cleanup.env.example" "$ENV_TARGET"
  echo "📄 Created $ENV_TARGET (edit owner/group/options as needed)."
else
  echo "📄 Environment file already exists at $ENV_TARGET (not overwritten)."
fi

systemctl --user daemon-reload
systemctl --user enable --now docling-cleanup.timer

echo "✅ Docling cleanup timer enabled. Ensure sudoers entry allows:"
echo "    ${USER} ALL=(ALL) NOPASSWD: ${REPO_ROOT}/scripts/maintenance/docling-shared-cleanup.sh --apply"
