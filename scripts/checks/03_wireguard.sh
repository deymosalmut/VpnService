#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

hr; log "WIREGUARD CHECK"
need_cmd ip

if ! command -v wg >/dev/null 2>&1; then
  warn "wg not installed on this host"
  exit 0
fi

log "Interfaces:"
ip link show | grep -E "^[0-9]+: " | sed 's/:$//'

hr; log "wg show ${WG_IFACE}:"
wg show "$WG_IFACE" || { err "wg show failed for ${WG_IFACE}"; exit 1; }

hr; log "wg dump ${WG_IFACE}:"
wg show "$WG_IFACE" dump || { err "wg dump failed for ${WG_IFACE}"; exit 1; }

hr; log "OK"
