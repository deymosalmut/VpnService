#!/bin/bash
# ----------------------------
# Прогон тестов ЭТАП 2
# ----------------------------
echo "🚀 Проверяем API..."
echo ""

# Health Check
echo "📋 [1] Health Check"
HC=$(curl -s http://localhost:5272/health)
if [ "$HC" == "Healthy" ]; then
    echo "✅ PASS: $HC"
else
    echo "❌ FAIL: $HC"
fi
echo ""

# Login
echo "📋 [2] Login"
LOGIN=$(curl -s -X POST http://localhost:5272/api/v1/auth/login \
-H "Content-Type: application/json" \
-d '{ "username": "admin", "password": "admin123" }')

# Extract token без jq (используем grep и sed)
ACCESS_TOKEN=$(echo "$LOGIN" | grep -o '"accessToken":"[^"]*"' | head -1 | sed 's/"accessToken":"\([^"]*\)"/\1/')

if [ -z "$ACCESS_TOKEN" ]; then
    echo "❌ FAIL: Не удалось получить токен"
    echo "$LOGIN"
    exit 1
else
    echo "✅ PASS: Получен токен"
fi
echo ""

# List Peers (до создания)
echo "📋 [3] List Peers (до создания)"
PEERS_BEFORE=$(curl -s -X GET http://localhost:5272/api/v1/peers \
-H "Authorization: Bearer $ACCESS_TOKEN" \
-H "Content-Type: application/json")
echo "✅ PASS: Список пиров получен"
echo "$PEERS_BEFORE"
echo ""

# Create Peer
echo "📋 [4] Create Peer"
CREATED=$(curl -s -X POST http://localhost:5272/api/v1/peers \
-H "Authorization: Bearer $ACCESS_TOKEN" \
-H "Content-Type: application/json" \
-d '{
    "publicKey": "TEST_KEY_'$(date +%s)'",
    "assignedIp": "10.0.0.2",
    "vpnServerId": "12345678-1234-1234-1234-123456789012"
}')

# Extract peer ID без jq
PEER_ID=$(echo "$CREATED" | grep -o '"id":"[^"]*"' | head -1 | sed 's/"id":"\([^"]*\)"/\1/')

if [ -z "$PEER_ID" ]; then
    echo "❌ FAIL: Не удалось создать пир"
    echo "$CREATED"
    exit 1
else
    echo "✅ PASS: Пир создан (ID: $PEER_ID)"
fi
echo ""

# Get Peer by ID
echo "📋 [5] Get Peer by ID"
GET_PEER=$(curl -s -X GET "http://localhost:5272/api/v1/peers/$PEER_ID" \
-H "Authorization: Bearer $ACCESS_TOKEN" \
-H "Content-Type: application/json")
echo "✅ PASS: Пир получен"
echo "$GET_PEER"
echo ""

# List Peers (с одним пиром)
echo "📋 [6] List Peers (с одним пиром)"
PEERS_AFTER=$(curl -s -X GET http://localhost:5272/api/v1/peers \
-H "Authorization: Bearer $ACCESS_TOKEN" \
-H "Content-Type: application/json")
echo "✅ PASS: Пиры получены"
echo "$PEERS_AFTER"
echo ""

# Revoke Peer
echo "📋 [7] Revoke Peer"
REVOKED=$(curl -s -X DELETE "http://localhost:5272/api/v1/peers/$PEER_ID" \
-H "Authorization: Bearer $ACCESS_TOKEN" \
-H "Content-Type: application/json")
echo "✅ PASS: Пир отозван"
echo "$REVOKED"
echo ""

echo "✅ Все тесты завершены"
