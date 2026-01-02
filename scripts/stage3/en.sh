#!/usr/bin/env bash
set -euo pipefail

API="http://localhost:5272"

echo "[1] Health"
curl -fsS "$API/health" && echo

echo "[2] Login"
LOGIN_JSON='{"username":"admin","password":"admin123"}'

TOKEN="$(curl -fsS "$API/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d "$LOGIN_JSON" | jq -r '.accessToken')"

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  echo "ERROR: token is empty. Login response invalid."
  exit 1
fi

echo "[3] Call protected admin wg endpoint"
curl -i "$API/api/v1/admin/wg/state?iface=wg1" \
  -H "Authorization: Bearer $TOKEN"
