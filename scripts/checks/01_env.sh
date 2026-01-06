#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

hr; log "ENV CHECK"
need_cmd uname
need_cmd bash
need_cmd curl
need_cmd dotnet

log "OS: $(uname -a)"
log "dotnet: $(dotnet --version)"
log "curl: $(curl --version | head -n 1)"

if command -v wg >/dev/null 2>&1; then
  log "wg: $(wg --version 2>/dev/null || true)"
else
  warn "wg not found (ok if this is API-only host)"
fi

if command -v psql >/dev/null 2>&1; then
  log "psql: $(psql --version)"
else
  warn "psql not found (db checks may be limited)"
fi

hr; log "OK"
