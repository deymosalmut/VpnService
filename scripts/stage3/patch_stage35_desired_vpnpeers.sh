#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

cat >scripts/stage3/stage3_05_desired_db_dump.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

source "scripts/lib/report.sh"
source "scripts/lib/appdb.sh"

APP_DB_ENV="${APP_DB_ENV:-$REPO_ROOT/infra/local/app-db.env}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"

report_init "stage35_desired_db_dump"
rc=0
{
  section "Stage 3.5 — DESIRED (DB) dump (read-only)"
  run_step "Load app DB env" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    echo \"PG_DATABASE=\$PG_DATABASE PG_USER=\$PG_USER PG_HOST=\$PG_HOST PG_PORT=\$PG_PORT PG_PASSWORD=\${PG_PASSWORD:+SET}\"
  "

  section "Detect schema capability (allowed_ips/endpoint/keepalive)"
  caps="$(bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -Atc \"
      select
        max(case when lower(column_name) like '%allowed%ip%' then 1 else 0 end) as has_allowed,
        max(case when lower(column_name) like '%endpoint%' then 1 else 0 end) as has_ep,
        max(case when lower(column_name) like '%keepalive%' then 1 else 0 end) as has_ka
      from information_schema.columns
      where table_schema not in ('pg_catalog','information_schema');
    \"
  " | tr -d '[:space:]' || true)"
  # caps format: "0|0|0" or "1|0|1"
  has_allowed="$(echo "$caps" | cut -d'|' -f1 || echo 0)"
  has_ep="$(echo "$caps" | cut -d'|' -f2 || echo 0)"
  has_ka="$(echo "$caps" | cut -d'|' -f3 || echo 0)"
  log "CAPS has_allowed=$has_allowed has_endpoint=$has_ep has_keepalive=$has_ka"

  section "Source table: public.\"VpnPeers\" (PublicKey)"
  # ensure table exists
  exists="$(bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -Atc \"
      select count(*) from information_schema.tables
      where table_schema='public' and table_name='VpnPeers';
    \"
  " | tr -d '[:space:]' || true)"
  [[ "${exists:-0}" == "1" ]] || { log "FAIL: table public.\"VpnPeers\" not found"; exit 12; }

  out="$OUT_DIR/stage35_desired_$(date +%Y-%m-%d_%H-%M-%S).tsv"

  # Desired TSV contract:
  # pub<TAB>allowed<TAB>endpoint<TAB>keepalive<TAB>enabled
  # If schema missing allowed fields => allowed/endpoint/keepalive blank; enabled=1
  run_step_tee "Export desired TSV (incomplete allowed data if not present in DB)" bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -AtF \$'\\t' -c \"
      select
        \\\"PublicKey\\\"::text as public_key,
        ''::text as allowed_ips,
        ''::text as endpoint,
        ''::text as keepalive,
        1 as enabled
      from public.\\\"VpnPeers\\\"
      order by \\\"PublicKey\\\";
    \" > '$out'
    wc -l '$out'
  "

  section "Summary"
  log "DESIRED_TABLE=public.\"VpnPeers\""
  log "DESIRED_FILE=$out"
  if [[ \"$has_allowed\" != \"1\" ]]; then
    log "INCOMPLETE_DESIRED=YES"
    log "NOTE=DB has no allowed_ips columns anywhere; Stage 3.5 will run in REMOVE-ONLY safe mode."
  else
    log "INCOMPLETE_DESIRED=NO"
  fi
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
SH

chmod +x scripts/stage3/stage3_05_desired_db_dump.sh
echo "OK patched: scripts/stage3/stage3_05_desired_db_dump.sh"
