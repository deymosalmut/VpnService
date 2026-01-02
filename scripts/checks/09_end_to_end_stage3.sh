#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

hr; log "STAGE 3 E2E"

need_cmd curl

log "[1] Health"
curl -sS "$API_BASE_URL/health" && echo

log "[2] Login"
resp="$(curl -sS -X POST "$API_BASE_URL/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}")"
echo "$resp"

token="$(echo "$resp" | sed -n 's/.*"accessToken":"\([^\"]*\)".*/\1/p')"
if [[ -z "$token" ]]; then
  err "Login failed or schema mismatch."
  exit 1
fi
save_token "$token"

log "[3] Admin WG State"
curl -i -sS "$API_BASE_URL/api/v1/admin/wg/state?iface=$WG_IFACE" \
  -H "Authorization: Bearer $token"
echo

hr; log "OK"
