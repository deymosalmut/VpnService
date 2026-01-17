#!/usr/bin/env bash
# PURPOSE: Create WireGuard peer via admin endpoint and validate config + QR + wg state
# EXPECTED OUTPUT: HTTP 200, config and qrDataUrl present, publicKey appears in wg state
# EXIT CODE: 0 on success, 1 on failure

set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

hr; log "CREATE PEER + QR SMOKE TEST"

need_cmd curl
need_cmd jq

bash "$(dirname "$0")/07_auth.sh"

token="$(load_token)"
if [[ -z "$token" ]]; then
  err "Could not load access token"
  exit 1
fi

peer_name="smoke-$(date +%s)"
req_body="{\"iface\":\"$WG_IFACE\",\"name\":\"$peer_name\"}"

resp="$(curl -sS -w "\n%{http_code}" -X POST "$API_BASE_URL/api/v1/admin/wg/peer" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $token" \
  -d "$req_body")"

status="${resp##*$'\n'}"
body="${resp%$'\n'*}"

if [[ "$status" != "200" ]]; then
  err "Expected HTTP 200, got $status"
  exit 1
fi

if ! echo "$body" | jq -e '.config' >/dev/null; then
  err "Response missing config"
  exit 1
fi

qr_url="$(echo "$body" | jq -r '.qrDataUrl // empty')"
if [[ -z "$qr_url" ]] || [[ "$qr_url" != data:image/png;base64,* ]]; then
  err "qrDataUrl missing or invalid"
  exit 1
fi

pubkey="$(echo "$body" | jq -r '.publicKey // empty')"
if [[ -z "$pubkey" ]]; then
  err "publicKey missing in response"
  exit 1
fi

config="$(echo "$body" | jq -r '.config // empty')"
if [[ -z "$config" ]]; then
  err "config missing in response"
  exit 1
fi

if ! echo "$config" | grep -q "\[Interface\]"; then
  err "config missing [Interface]"
  exit 1
fi

if ! echo "$config" | grep -q "PrivateKey"; then
  err "config missing PrivateKey"
  exit 1
fi

if ! echo "$config" | grep -q "Address"; then
  err "config missing Address"
  exit 1
fi

if ! echo "$config" | grep -q "\[Peer\]"; then
  err "config missing [Peer]"
  exit 1
fi

state="$(curl -sS -H "Authorization: Bearer $token" "$API_BASE_URL/api/v1/admin/wg/state")"
if ! echo "$state" | jq -e --arg pubkey "$pubkey" '.peers[]? | select(.publicKey == $pubkey)' >/dev/null; then
  err "publicKey not found in wg state"
  exit 1
fi

hr; log "PASS"
exit 0
