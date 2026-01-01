#!/bin/bash
# ----------------------------
# Проверка ЭТАП 2 (OS-независимость)
# ----------------------------
echo "🔍 Проверяем код на OS-зависимости..."
echo ""

ISSUES=0

# Проверка на WireGuard CLI команды
if grep -R "wg " ../VpnService/*.cs ../VpnService/*/*.cs ../VpnService/*/*/*.cs 2>/dev/null | grep -v "//" | grep -v "swagger"; then
    echo "⚠️  Найдены ссылки на 'wg' команду"
    ISSUES=$((ISSUES + 1))
else
    echo "✅ 'wg' команда не найдена"
fi
echo ""

# Проверка на wireguard
if grep -R "wireguard" ../VpnService 2>/dev/null | grep -v "//" | grep -v "README" | grep -v ".md"; then
    echo "⚠️  Найдены ссылки на 'wireguard'"
    ISSUES=$((ISSUES + 1))
else
    echo "✅ 'wireguard' не найдено"
fi
echo ""

# Проверка на iptables
if grep -R "iptables" ../VpnService 2>/dev/null | grep -v "//" | grep -v "README" | grep -v ".md"; then
    echo "⚠️  Найдены ссылки на 'iptables'"
    ISSUES=$((ISSUES + 1))
else
    echo "✅ 'iptables' не найдено"
fi
echo ""

# Проверка на sudo
if grep -R "sudo" ../VpnService 2>/dev/null | grep -v "//" | grep -v "README" | grep -v ".md"; then
    echo "⚠️  Найдены ссылки на 'sudo'"
    ISSUES=$((ISSUES + 1))
else
    echo "✅ 'sudo' не найдено"
fi
echo ""

# Проверка на /etc/
if grep -R '"/etc/' ../VpnService 2>/dev/null | grep -v "//" | grep -v "README" | grep -v ".md"; then
    echo "⚠️  Найдены ссылки на '/etc/'"
    ISSUES=$((ISSUES + 1))
else
    echo "✅ '/etc/' не найдено"
fi
echo ""

# Проверка на Linux-специфичные пути
if grep -R '"/proc/' ../VpnService 2>/dev/null | grep -v "//" | grep -v "README" | grep -v ".md"; then
    echo "⚠️  Найдены ссылки на '/proc/'"
    ISSUES=$((ISSUES + 1))
else
    echo "✅ '/proc/' не найдено"
fi
echo ""

if [ $ISSUES -eq 0 ]; then
    echo "✅ PASS: Код полностью OS-независим"
    exit 0
else
    echo "❌ FAIL: Найдено $ISSUES проблем(ы)"
    exit 1
fi
