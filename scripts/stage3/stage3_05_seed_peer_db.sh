#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

source "scripts/lib/report.sh"
source "scripts/lib/appdb.sh"

APP_DB_ENV="${APP_DB_ENV:-$REPO_ROOT/infra/local/app-db.env}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
ts(){ date +"%Y-%m-%d_%H-%M-%S"; }

report_init "stage35_seed_peer_db"
rc=0
{
  section "Stage 3.5 — SEED 1 peer into DB (controlled)"

  run_step "Load app DB env" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    echo \"PG_DATABASE=\$PG_DATABASE PG_USER=\$PG_USER PG_HOST=\$PG_HOST PG_PORT=\$PG_PORT PG_PASSWORD=\${PG_PASSWORD:+SET}\"
  "

  section "Precheck: required tables exist"
  run_step "Check public.\"VpnPeers\" exists" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -Atc \"select count(*) from information_schema.tables where table_schema='public' and table_name='VpnPeers';\" | grep -qx '1'
  "
  run_step "Check public.\"VpnServers\" exists" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -Atc \"select count(*) from information_schema.tables where table_schema='public' and table_name='VpnServers';\" | grep -qx '1'
  "

  section "Resolve VpnServerId (must exist)"
  VPN_SERVER_ID="$(bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -Atc 'select \"Id\" from public.\"VpnServers\" order by \"CreatedAt\" nulls last, \"Id\" limit 1;'
  " | tail -n 1 | tr -d '[:space:]' || true)"
  if [[ -z "$VPN_SERVER_ID" ]]; then
    log "FAIL: no rows in public.\"VpnServers\". Cannot seed peer because VpnServerId is NOT NULL."
    log "Action: create a Stage 3.5 seed for VpnServers (we will add a script) and rerun."
    exit 15
  fi
  log "VPN_SERVER_ID=$VPN_SERVER_ID"

  section "Generate WireGuard keypair (private key stored on disk, not printed)"
  keydir="$OUT_DIR/stage35_seed_keys_$(ts)"
  mkdir -p "$keydir"
  chmod 700 "$keydir"

  run_step_tee "wg genkey + pubkey" bash -lc "
    set -Eeuo pipefail
    priv=\$(wg genkey)
    pub=\$(printf '%s' \"\$priv\" | wg pubkey)
    printf '%s\n' \"\$priv\" > \"$keydir/privatekey\"
    chmod 600 \"$keydir/privatekey\"
    printf '%s\n' \"\$pub\"  > \"$keydir/publickey\"
    echo \"PUBLIC_KEY=\$pub\"
    echo \"KEY_DIR=$keydir\"
  "

  PUB="$(grep -E '^PUBLIC_KEY=' "$REPORT_FILE" | tail -n 1 | cut -d= -f2 || true)"
  [[ -n "$PUB" ]] || { log "FAIL: cannot read generated PUBLIC_KEY from report"; exit 20; }

  NEW_UUID="$(python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)"
  ASSIGNED_IP="$(bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    n=\$(psql_app -Atc 'select count(*) from public.\"VpnPeers\";' | tail -n 1 | tr -d '[:space:]')
    echo \"10.8.0.\$((100 + n))\"
  " | tail -n 1 | tr -d '[:space:]' || true)"
  [[ -n "$ASSIGNED_IP" ]] || { log "FAIL: cannot compute AssignedIp"; exit 21; }

  STATUS_VAL=1

  section "SAFETY GATE"
  load_app_db_env "$APP_DB_ENV"
  log "Target DB: $PG_DATABASE @ $PG_HOST:$PG_PORT user=$PG_USER"
  log "This will INSERT 1 row into public.\"VpnPeers\":"
  log "  Id=$NEW_UUID"
  log "  PublicKey=$PUB"
  log "  AssignedIp=$ASSIGNED_IP"
  log "  Status=$STATUS_VAL"
  log "  VpnServerId=$VPN_SERVER_ID"
  log "Type SEED to continue."
  read -r -p "> " gate
  [[ "$gate" == "SEED" ]] || { log "Abort: gate not passed."; exit 30; }

  section "Insert peer (idempotent by PublicKey)"
  run_step_tee "INSERT if not exists" bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'

    psql_app -v ON_ERROR_STOP=1 -Atc \"
      insert into public.\\\"VpnPeers\\\"(\\\"Id\\\",\\\"PublicKey\\\",\\\"AssignedIp\\\",\\\"Status\\\",\\\"VpnServerId\\\")
      select
        '$NEW_UUID'::uuid,
        '$PUB',
        '$ASSIGNED_IP',
        $STATUS_VAL,
        '$VPN_SERVER_ID'::uuid
      where not exists (select 1 from public.\\\"VpnPeers\\\" where \\\"PublicKey\\\"='$PUB');
    \"

    echo 'DB_COUNT='\"\$(psql_app -Atc 'select count(*) from public.\"VpnPeers\";')\"
  "

  section "DONE"
  log "SEEDED_PUBLIC_KEY=$PUB"
  log "ASSIGNED_IP=$ASSIGNED_IP"
  log "VPN_SERVER_ID=$VPN_SERVER_ID"
  log "KEY_DIR=$keydir"
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
