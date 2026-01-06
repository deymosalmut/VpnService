#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
OP_USER="${OP_USER:-vboxuser}"

echo ">>> Fix permissions for operator user"
echo "REPO_ROOT=$REPO_ROOT"
echo "OP_USER=$OP_USER"

# Ensure user exists
id "$OP_USER" >/dev/null 2>&1 || { echo "ERROR: user not found: $OP_USER"; exit 2; }

# Create group (idempotent)
groupadd -f vpnops

# Add operator to group
usermod -aG vpnops "$OP_USER"

# Make repo group-owned and group-writable where needed
chgrp -R vpnops "$REPO_ROOT"

# Reports must be writable
mkdir -p "$REPO_ROOT/reports"
chmod 2775 "$REPO_ROOT/reports"
chgrp vpnops "$REPO_ROOT/reports"

# Allow operator to execute scripts
find "$REPO_ROOT/scripts" -type d -print0 | xargs -0 chmod 2775
find "$REPO_ROOT/scripts" -type f -name "*.sh" -print0 | xargs -0 chmod 775

# Allow reading env files (but keep them not world-readable)
if [[ -d "$REPO_ROOT/infra/local" ]]; then
  chgrp -R vpnops "$REPO_ROOT/infra/local"
  chmod 2750 "$REPO_ROOT/infra/local"
  chmod 640 "$REPO_ROOT/infra/local/"*.env 2>/dev/null || true
fi

echo "OK permissions adjusted."
echo "IMPORTANT: operator must re-login to pick up group membership (or run: newgrp vpnops)."
