#!/bin/bash

# Запуск API в фоне
echo "🚀 Запускаю VPN Service API..."
cd /c/Users/aslon/Desktop/VpnService
timeout 60 dotnet run --project VpnService.Api -c Release > /tmp/api.log 2>&1 &
API_PID=$!
sleep 5

echo "✅ API запущен (PID: $API_PID)"
echo ""

# Тест 1: Health check
echo "📋 Тест 1: Health Check"
curl -s http://localhost:5272/health
echo ""
echo ""

# Тест 2: Login
echo "📋 Тест 2: Login (admin:admin123)"
LOGIN_RESPONSE=$(curl -s -X POST http://localhost:5272/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "password": "admin123"
  }')
echo "$LOGIN_RESPONSE" | head -5
ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"accessToken":"[^"]*' | cut -d'"' -f4)
echo ""
echo "Access Token: ${ACCESS_TOKEN:0:50}..."
echo ""

# Тест 3: List peers (пусто)
echo "📋 Тест 3: List Peers (должно быть пусто)"
curl -s http://localhost:5272/api/v1/peers | head -10
echo ""
echo ""

# Тест 4: Create peer
echo "📋 Тест 4: Create Peer"
PEER_RESPONSE=$(curl -s -X POST http://localhost:5272/api/v1/peers \
  -H "Content-Type: application/json" \
  -d '{
    "publicKey": "wGqFjr2Ty9l5KqQ+Z0pM8x9nY2vB1hK3jL4oP6sQ8tR9u=",
    "assignedIp": "10.0.0.2",
    "vpnServerId": "00000000-0000-0000-0000-000000000001"
  }')
echo "$PEER_RESPONSE"
PEER_ID=$(echo "$PEER_RESPONSE" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
echo ""
echo "Peer ID: $PEER_ID"
echo ""

# Тест 5: List peers (теперь не пусто)
echo "📋 Тест 5: List Peers (теперь с одним пиром)"
curl -s http://localhost:5272/api/v1/peers
echo ""
echo ""

# Тест 6: Get peer by ID
echo "📋 Тест 6: Get Peer by ID ($PEER_ID)"
curl -s http://localhost:5272/api/v1/peers/$PEER_ID
echo ""
echo ""

# Тест 7: Revoke peer
echo "📋 Тест 7: Revoke Peer"
curl -s -X DELETE http://localhost:5272/api/v1/peers/$PEER_ID
echo ""
echo ""

# Завершение
echo "✅ Все тесты завершены!"
kill $API_PID 2>/dev/null
echo ""
echo "📊 Логи API:"
tail -20 /tmp/api.log
