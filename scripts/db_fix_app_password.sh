#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT_DIR="${REPORT_DIR:-$REPO_ROOT/reports}"
mkdir -p "$REPORT_DIR"

PG_USER="${PG_USER:-vpnservice}"
PG_DB="${PG_DB:-vpnservice}"
PG_HOST="${PG_HOST:-127.0.0.1}"
PG_PORT="${PG_PORT:-5432}"

# Local secret file (gitignored by design)
SECRETS_DIR="$REPO_ROOT/infra/local"
SECRETS_FILE="$SECRETS_DIR/app-db.env"
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

ts="$(date -u +"%Y-%m-%d_%H-%M-%S")"
REPORT="$REPORT_DIR/report_db_fix_app_password_${ts}.log"
touch "$REPORT"

YELLOW='\033[1;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
header(){ echo -e "\n${YELLOW}>>> $1${NC}" | tee -a "$REPORT"; }
run(){ header "$1"; shift; echo "CMD: $*" | tee -a "$REPORT"; set +e; "$@" 2>&1 | tee -a "$REPORT"; rc=${PIPESTATUS[0]}; set -e; echo "STATUS: $rc" | tee -a "$REPORT"; return $rc; }

mask(){ local v="${1:-}"; [[ -z "$v" ]] && echo "<empty>" && return; echo "${v:0:2}***"; }

header "DB: fix app password (no manual input)"
echo "REPO_ROOT: $REPO_ROOT" | tee -a "$REPORT"
echo "PG_USER=$PG_USER PG_DB=$PG_DB PG_HOST=$PG_HOST PG_PORT=$PG_PORT" | tee -a "$REPORT"

# 1) Ensure role exists
run "DB(admin/socket): ensure role exists" sudo -u postgres psql -v ON_ERROR_STOP=1 -Atc \
  "SELECT 1 FROM pg_roles WHERE rolname='${PG_USER}'" >/dev/null || {
    run "DB(admin/socket): create role ${PG_USER}" sudo -u postgres psql -v ON_ERROR_STOP=1 -c \
      "CREATE ROLE ${PG_USER} WITH LOGIN;" || true
  }

# 2) Generate new deterministic password (timestamp-based)
NEW_PWD="${PG_USER}_pwd_${ts//[: -]/}"
header "Setting new password for role ${PG_USER}"
echo "NEW_PASSWORD: $(mask "$NEW_PWD")" | tee -a "$REPORT"

run "DB(admin/socket): ALTER ROLE password" sudo -u postgres psql -v ON_ERROR_STOP=1 -c \
  "ALTER ROLE ${PG_USER} WITH LOGIN PASSWORD '${NEW_PWD}';"

# 3) Ensure DB exists and owned by app user (optional, safe)
run "DB(admin/socket): ensure db exists" sudo -u postgres psql -v ON_ERROR_STOP=1 -Atc \
  "SELECT 1 FROM pg_database WHERE datname='${PG_DB}'" >/dev/null || \
  run "DB(admin/socket): create db ${PG_DB}" sudo -u postgres psql -v ON_ERROR_STOP=1 -c \
    "CREATE DATABASE ${PG_DB} OWNER ${PG_USER};"

run "DB(admin/socket): set db owner" sudo -u postgres psql -v ON_ERROR_STOP=1 -c \
  "ALTER DATABASE ${PG_DB} OWNER TO ${PG_USER};" || true

# 4) Test app TCP login using new password
run "DB(app/tcp): select 1" bash -lc \
  "PGPASSWORD='${NEW_PWD}' psql -h '${PG_HOST}' -p '${PG_PORT}' -U '${PG_USER}' -d '${PG_DB}' -v ON_ERROR_STOP=1 -Atc 'select 1;'"

# 5) Persist secret locally (gitignored)
header "Persisting app DB env to ${SECRETS_FILE}"
cat > "$SECRETS_FILE" <<EOF
# Local secrets (DO NOT COMMIT)
export PG_HOST="${PG_HOST}"
export PG_PORT="${PG_PORT}"
export PG_DB="${PG_DB}"
export PG_USER="${PG_USER}"
export PG_PASSWORD="${NEW_PWD}"
EOF
chmod 600 "$SECRETS_FILE"

echo -e "${GREEN}OK${NC} Saved local env: $SECRETS_FILE" | tee -a "$REPORT"
echo "Next: source it before running preflight/migrations:" | tee -a "$REPORT"
echo "  source '$SECRETS_FILE'" | tee -a "$REPORT"
echo -e "\nDone. Report: $REPORT"
