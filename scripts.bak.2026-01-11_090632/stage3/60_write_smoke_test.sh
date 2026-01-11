#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

ENV_FILE="$SCRIPT_DIR/00_env"
load_env "$ENV_FILE"

require_cmd curl
require_cmd jq

log "[1] Health"
curl -fsS "$API_URL/health" >/dev/null
echo "OK"

log "[2] Login"
LOGIN_JSON="$(jq -n --arg u "$ADMIN_USERNAME" --arg p "$ADMIN_PASSWORD" '{username:$u,password:$p}')"
LOGIN_RESP="$(curl -fsS -X POST "$API_URL/api/v1/auth/login" -H "Content-Type: application/json" -d "$LOGIN_JSON")"
TOKEN="$(echo "$LOGIN_RESP" | jq -r '.accessToken')"
[[ -n "$TOKEN" && "$TOKEN" != "null" ]] || die "Login failed: $LOGIN_RESP"

log "[3] Generate test peer keypair on server (for test only)"
TEST_PRIV="$(wg genkey)"
TEST_PUB="$(echo "$TEST_PRIV" | wg pubkey)"
TEST_ALLOWED="10.0.0.250/32"

log "Test pubkey: $TEST_PUB"
log "Allowed: $TEST_ALLOWED"

log "[4] Call add peer endpoint"
ADD_JSON="$(jq -n --arg i "$WG_IFACE" --arg k "$TEST_PUB" --arg a "$TEST_ALLOWED" '{interface:$i, publicKey:$k, allowedIpCidr:$a}')"
curl -fsS -X POST "$API_URL/api/v1/admin/wg/peer/add" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$ADD_JSON" | jq .

log "[5] Verify peer exists in wg dump"
bash "$WG_DUMP_SCRIPT" "$WG_IFACE" | jq -e --arg k "$TEST_PUB" '.peers[] | select(.publicKey==$k)' >/dev/null \
  || die "Peer not found in wg dump after add"

log "[6] Call remove peer endpoint"
REM_JSON="$(jq -n --arg i "$WG_IFACE" --arg k "$TEST_PUB" '{interface:$i, publicKey:$k}')"
curl -fsS -X POST "$API_URL/api/v1/admin/wg/peer/remove" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$REM_JSON" | jq .

log "[7] Verify peer removed"
if bash "$WG_DUMP_SCRIPT" "$WG_IFACE" | jq -e --arg k "$TEST_PUB" '.peers[] | select(.publicKey==$k)' >/dev/null; then
  die "Peer still present in wg dump after remove"
fi

log "DONE: write-path smoke test OK"
