#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

hr; log "DB CHECK"

if ! command -v psql >/dev/null 2>&1; then
  warn "psql not installed; skipping DB checks"
  exit 0
fi

need_cmd systemctl

log "postgresql: $(systemctl is-active postgresql || true)"
hr

sudo -u postgres psql -c "\l" | head -n 20 || warn "Cannot list databases (check permissions)"

hr; log "OK (with possible warnings)"
