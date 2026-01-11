#!/usr/bin/env bash
set -euo pipefail

IFACE="${1:-wg1}"

TARGET_DIR="/opt/vpn-adapter"
mkdir -p "$TARGET_DIR"

# копируем из репо в /opt
cp "$(dirname "$0")/wg_dump.sh" "$TARGET_DIR/wg_dump.sh"
chmod +x "$TARGET_DIR/wg_dump.sh"

echo "Installed: $TARGET_DIR/wg_dump.sh"
echo "Test run:"
"$TARGET_DIR/wg_dump.sh" "$IFACE"
