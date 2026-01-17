#!/usr/bin/env bash
# PURPOSE: Verify /admin endpoint returns valid HTML with correct content-type
# EXPECTED OUTPUT: HTTP 200, Content-Type: text/html, page contains "VPN Service Admin"
# EXIT CODE: 0 on success, 1 on failure

set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

hr; log "ADMIN PANEL SMOKE TEST"

need_cmd curl

url="$API_BASE_URL/admin"

log "Fetching $url"
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

log "Checking for stable marker: \"VPN Service Admin\""
if ! curl -sS "$url" | grep -q "VPN Service Admin"; then
  err "Expected page to contain \"VPN Service Admin\""
  exit 1
fi

log "First 10 lines of HTML:"
curl -sS "$url" | head -n 10

hr; log "✓ PASS"
exit 0
