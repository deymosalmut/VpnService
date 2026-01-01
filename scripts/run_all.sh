#!/bin/bash
# =========================================
# Master Script — Полная проверка ЭТАП 2
# =========================================
set -e

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPTS_DIR"

echo "════════════════════════════════════════════════"
echo "   🚀 VPN Service ЭТАП 2 — Полная проверка"
echo "════════════════════════════════════════════════"
echo ""

# Функция для остановки API при завершении
cleanup() {
    echo ""
    echo "🛑 Остановка API..."
    ./stop_api.sh 2>/dev/null || true
}
trap cleanup EXIT

# 1. Проверка зависимостей
echo "📌 [1/5] Проверка зависимостей..."
if ! command -v dotnet &> /dev/null; then
    echo "❌ FAIL: .NET SDK не установлен"
    exit 1
fi
if ! command -v curl &> /dev/null; then
    echo "❌ FAIL: curl не установлен"
    exit 1
fi
if ! command -v jq &> /dev/null; then
    echo "❌ FAIL: jq не установлен"
    exit 1
fi
echo "✅ PASS: Все зависимости установлены"
echo ""

# 2. Сборка проекта
echo "📌 [2/5] Сборка проекта..."
cd ..
dotnet build > /dev/null 2>&1 || {
    echo "❌ FAIL: Ошибка при сборке"
    exit 1
}
echo "✅ PASS: Проект собран"
cd scripts
echo ""

# 3. Запуск API
echo "📌 [3/5] Запуск API..."
./run_api.sh > /dev/null 2>&1
sleep 3

# Проверка, запущен ли API
if ! curl -s http://localhost:5272/health > /dev/null 2>&1; then
    echo "❌ FAIL: API не запустился"
    exit 1
fi
echo "✅ PASS: API запущен"
echo ""

# 4. Прогон тестов
echo "📌 [4/5] Прогон тестов API..."
./test_api.sh
echo ""

# 5. Проверка OS-зависимостей
echo "📌 [5/5] Проверка OS-независимости..."
./verify_stage2.sh
echo ""

# 6. Сбор отчета
echo "📌 [6/6] Генерация отчета..."
./generate_report.sh
echo ""

echo "════════════════════════════════════════════════"
echo "   🎯 ЭТАП 2 полностью готов к Ubuntu"
echo "════════════════════════════════════════════════"
