#!/bin/bash
# ----------------------------
# Запуск VPN Service API
# ----------------------------
echo "🚀 Запускаю VPN Service API..."
dotnet run --project ../VpnService.Api > /tmp/vpnservice.log 2>&1 &
API_PID=$!
echo "✅ API запущен (PID: $API_PID)"
echo "Логи: /tmp/vpnservice.log"
echo $API_PID > /tmp/vpnservice.pid
