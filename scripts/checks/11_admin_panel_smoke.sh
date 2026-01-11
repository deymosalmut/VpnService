#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

hr; log "ADMIN PANEL SMOKE"

need_cmd curl

url="$API_BASE_URL/admin"

log "HEAD $url"
headers="$(curl -sS -I "$url")"
echo "$headers"

if ! echo "$headers" | head -n 1 | grep -q " 200"; then
  err "Expected HTTP 200 for $url"
  exit 1
fi

if ! echo "$headers" | grep -qi "^Content-Type: text/html"; then
  err "Expected Content-Type: text/html"
  exit 1
fi

log "First 15 lines of HTML:"
curl -sS "$url" | sed -n '1,15p'

hr; log "OK"
