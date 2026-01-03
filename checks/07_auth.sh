#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

hr; log "AUTH TEST (login + save token)"

need_cmd curl

log "Calling login: $API_BASE_URL/api/v1/auth/login"
resp="$(curl -sS -X POST "$API_BASE_URL/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}")"

echo "$resp"

token="$(echo "$resp" | sed -n 's/.*"accessToken":"\([^\"]*\)".*/\1/p')"

if [[ -z "$token" ]]; then
  err "Could not parse accessToken. Check request schema (username/password vs email/password)."
  exit 1
fi

save_token "$token"
log "TOKEN saved to $TOKEN_FILE"
log "Export for current shell:"
echo "export TOKEN=\"$(load_token)\""

hr; log "OK"
