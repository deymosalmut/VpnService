#!/bin/bash
# ----------------------------
# Остановка API по PID
# ----------------------------
if [ -f /tmp/vpnservice.pid ]; then
    PID=$(cat /tmp/vpnservice.pid)
    kill $PID 2>/dev/null && echo "✅ API (PID: $PID) остановлен"
    rm /tmp/vpnservice.pid
else
    echo "❌ PID файл не найден. API не запущен?"
fi
