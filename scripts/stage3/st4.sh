#!/bin/bash
set -e

API="http://127.0.0.1:5001"
USER="testuse1r"
PASS="SecurePass2026"

echo "[1] Health check"
curl -s "$API/health"
echo ""

echo "[2] Login and set access token"
RESP=$(curl -s -X POST "$API/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"'"$USER"'","password":"'"$PASS"'"}')

echo "$RESP"
echo ""

TOKEN=$(echo "$RESP" | jq -r '.accessToken // empty')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "❌ Login failed"
  exit 1
fi

echo "✅ Access token received: ${TOKEN:0:20}..."
