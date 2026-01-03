#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

hr; log "SERVICES CHECK"
need_cmd systemctl

for svc in ssh postgresql "wg-quick@${WG_IFACE}"; do
  if systemctl list-unit-files | grep -q "^${svc}\.service"; then
    log "$svc: $(systemctl is-active "$svc" || true)"
  else
    warn "$svc: unit not found"
  fi
done

hr; log "OK (with possible warnings)"
