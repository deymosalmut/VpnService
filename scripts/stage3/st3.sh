3#!/usr/bin/env bash
set -euo pipefail

API_URL="http://localhost:5272"
IFACE="${1:-wg1}"

EMAIL="${EMAIL:-admin}"
PASSWORD="${PASSWORD:-admin123}"

echo "=============================="
echo " VPN Service — Stage 3 Check"
echo "=============================="
echo

echo "[1] Health check"
curl -fsS "$API_URL/health"
echo
echo

echo "[2] Login and get access token"
LOGIN_JSON=$(curl -fsS -X POST "$API_URL/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")

echo "$LOGIN_JSON"
echo

TOKEN=$(echo "$LOGIN_JSON" | python3 - <<'PY'
import sys, json
print(json.load(sys.stdin)["accessToken"])
PY
)

if [ -z "$TOKEN" ]; then
  echo "ERROR: access token not received"
  exit 1
fi

echo "[3] Call API WG state endpoint (iface=$IFACE)"
curl -fsS "$API_URL/api/v1/admin/wg/state?iface=$IFACE" \
  -H "Authorization: Bearer $TOKEN"
echo
echo

echo "[4] Local wg_dump.sh (for comparison)"
if [ -x "/opt/vpn-adapter/wg_dump.sh" ]; then
  /opt/vpn-adapter/wg_dump.sh "$IFACE"
else
  echo "WARNING: /opt/vpn-adapter/wg_dump.sh not found"
fi

echo
echo "DONE"
