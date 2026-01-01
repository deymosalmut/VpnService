#!/bin/bash
# ----------------------------
# Настройка PostgreSQL и миграции
# ----------------------------
DB_NAME="vpnservice"
DB_USER="vpnuser"
DB_PASS="vpnpass"

echo "📦 Создаем БД и пользователя..."
sudo -u postgres psql <<EOF
CREATE DATABASE $DB_NAME;
CREATE USER $DB_USER WITH ENCRYPTED PASSWORD '$DB_PASS';
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF

echo "📌 Применяем миграции..."
dotnet ef database update --project ../VpnService.Infrastructure
echo "✅ База данных готова"
