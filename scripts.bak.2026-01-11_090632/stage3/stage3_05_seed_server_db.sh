#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

source "scripts/lib/report.sh"
source "scripts/lib/appdb.sh"

APP_DB_ENV="${APP_DB_ENV:-$REPO_ROOT/infra/local/app-db.env}"
IFACE="${IFACE:-wg1}"

# defaults (can override via env)
SERVER_NAME="${SERVER_NAME:-$IFACE}"
SERVER_NETWORK="${SERVER_NETWORK:-10.8.0.0/24}"
SERVER_GATEWAY="${SERVER_GATEWAY:-10.8.0.1/32}"

report_init "stage35_seed_server_db"
rc=0
{
  section "Stage 3.5 — SEED 1 server into DB (controlled)"

  run_step "Load app DB env" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    echo \"PG_DATABASE=\$PG_DATABASE PG_USER=\$PG_USER PG_HOST=\$PG_HOST PG_PORT=\$PG_PORT\"
  "

  # sanity: table exists
  run_step "Precheck: public.\"VpnServers\" exists" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -Atc \"select count(*) from information_schema.tables where table_schema='public' and table_name='VpnServers';\" | grep -qx '1'
  "

  NEW_UUID="$(python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)"

  section "SAFETY GATE"
  load_app_db_env "$APP_DB_ENV"
  log "Target DB: $PG_DATABASE @ $PG_HOST:$PG_PORT user=$PG_USER"
  log "This will INSERT 1 row into public.\"VpnServers\""
  log "  Id      = $NEW_UUID"
  log "  Name    = $SERVER_NAME"
  log "  Gateway = $SERVER_GATEWAY"
  log "  Network = $SERVER_NETWORK"
  log "Type SEED to continue."
  read -r -p "> " gate
  [[ "$gate" == "SEED" ]] || { log "Abort: gate not passed."; exit 30; }

  run_step_tee "Insert server (Id+Name+Gateway+Network) + count" bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -v ON_ERROR_STOP=1 -Atc \"
      insert into public.\\\"VpnServers\\\"(\\\"Id\\\",\\\"Name\\\",\\\"Gateway\\\",\\\"Network\\\")
      values (
        '$NEW_UUID'::uuid,
        '$(printf "%s" "$SERVER_NAME" | sed "s/'/''/g")',
        '$(printf "%s" "$SERVER_GATEWAY" | sed "s/'/''/g")',
        '$(printf "%s" "$SERVER_NETWORK" | sed "s/'/''/g")'
      );
    \"
    echo 'DB_COUNT='\"\$(psql_app -Atc 'select count(*) from public.\"VpnServers\";')\"
  "

  section "DONE"
  log "SEEDED_SERVER_ID=$NEW_UUID"
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
