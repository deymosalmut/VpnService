#!/bin/bash
# ----------------------------
# Заполнение тестовыми данными
# ----------------------------
echo "⏳ Ожидаю запуска API..."
sleep 2

LOGIN_RESPONSE=$(curl -s -X POST http://localhost:5272/api/v1/auth/login \
-H "Content-Type: application/json" \
-d '{ "username": "admin", "password": "admin123" }')

# Extract token без jq
ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"accessToken":"[^"]*"' | head -1 | sed 's/"accessToken":"\([^"]*\)"/\1/')

if [ -z "$ACCESS_TOKEN" ]; then
    echo "❌ Не удалось получить токен доступа"
    exit 1
fi

echo "📋 Создаем тестовый пир..."
RESPONSE=$(curl -s -X POST http://localhost:5272/api/v1/peers \
-H "Authorization: Bearer $ACCESS_TOKEN" \
-H "Content-Type: application/json" \
-d '{
    "publicKey": "SEED_KEY_1",
    "assignedIp": "10.0.0.3",
    "vpnServerId": "12345678-1234-1234-1234-123456789012"
}')

echo "$RESPONSE"

if echo "$RESPONSE" | grep -q '"id"'; then
    echo "✅ Пир создан"
else
    echo "❌ Ошибка при создании пира"
fi
