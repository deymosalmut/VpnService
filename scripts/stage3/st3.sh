#!/usr/bin/env bash
set -e

API="http://localhost:5272"
USER="admin"
PASS="admin123"

echo "[1] Health check"
curl -s $API/health
echo

echo "[2] Login"
RESP=$(curl -s -X POST $API/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USER\",\"password\":\"$PASS\"}")

echo "$RESP"

TOKEN=$(echo "$RESP" | jq -r '.accessToken')

if [ "$TOKEN" = "null" ]; then
  echo "❌ Login failed"
  exit 1
fi

echo "✅ Access token received"
