#!/bin/bash
set -e

# Configuration
API="${1:-http://localhost:5001}"
USERNAME="${2:-admin}"
PASSWORD="${3:-admin123}"

echo "=========================================="
echo "VPN Service Auth Test Script"
echo "=========================================="
echo "API: $API"
echo "User: $USERNAME"
echo ""

# Step 1: Health check
echo "[1] Checking API health..."
if ! curl -s -f "$API/health" > /dev/null 2>&1; then
    echo "❌ API is not responding at $API"
    echo "   Make sure the API is running:"
    echo "   cd VpnService && dotnet run --project VpnService.Api"
    exit 1
fi
echo "✅ API is healthy"
echo ""

# Step 2: Get login endpoint schema (check required fields)
echo "[2] Testing login endpoint..."
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{}')

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

echo "Response (HTTP $HTTP_CODE):"
echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
echo ""

# Step 3: Try login with provided credentials
echo "[3] Attempting login..."
LOGIN_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$API/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}")

LOGIN_HTTP_CODE=$(echo "$LOGIN_RESPONSE" | tail -n1)
LOGIN_BODY=$(echo "$LOGIN_RESPONSE" | sed '$d')

echo "Response (HTTP $LOGIN_HTTP_CODE):"
echo "$LOGIN_BODY" | jq . 2>/dev/null || echo "$LOGIN_BODY"
echo ""

# Step 4: Extract token if successful
if [ "$LOGIN_HTTP_CODE" = "200" ]; then
    TOKEN=$(echo "$LOGIN_BODY" | jq -r '.accessToken // .token // empty')
    
    if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
        echo "✅ Login successful!"
        echo "Token: ${TOKEN:0:30}..."
        echo ""
        echo "Export token for next steps:"
        echo "export TOKEN=\"$TOKEN\""
    else
        echo "⚠️  Login returned 200 but no token found"
        echo "Response structure may be different"
    fi
else
    echo "❌ Login failed (HTTP $LOGIN_HTTP_CODE)"
    echo "Check username and password"
fi
# Сохраняем токен в файл для других скриптов
echo "$TOKEN" > .token
chmod 600 .token

echo "Token saved to .token"

echo ""
echo "=========================================="
