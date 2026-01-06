#!/usr/bin/env bash
set -Eeuo pipefail
<<<<<<< HEAD

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

REPORT_DIR="${REPORT_DIR:-$REPO_ROOT/reports}"
export REPORT_DIR

source "scripts/lib/report.sh"
source "scripts/lib/appdb.sh"

APP_DB_ENV="$REPO_ROOT/infra/local/app-db.env"
STATE_FILE="$REPORT_DIR/stage35_last_run.env"

COLS=""

update_state() {
  local key="$1"
  local value="$2"
  local tmp="${STATE_FILE}.tmp"
  if [[ -f "$STATE_FILE" ]]; then
    awk -v k="$key" -F= '$1!=k {print}' "$STATE_FILE" > "$tmp"
  else
    : > "$tmp"
  fi
  printf '%s=%q\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$STATE_FILE"
}

col_exists() {
  local name="$1"
  echo "$COLS" | awk -F'|' -v n="$name" '$1==n {found=1} END{exit !found}'
}

col_type() {
  local name="$1"
  echo "$COLS" | awk -F'|' -v n="$name" '$1==n {print $2; exit}'
}

col_udt() {
  local name="$1"
  echo "$COLS" | awk -F'|' -v n="$name" '$1==n {print $3; exit}'
}

main() {
  section "Stage 3.5 desired DB dump"

  section "Load app DB env"
  if ! load_app_db_env "$APP_DB_ENV"; then
    log "ERROR: failed to load app DB env."
    return 10
  fi
  log "DB: $PG_HOST:$PG_PORT/$PG_DATABASE user=$PG_USER"

  section "Detect peers table"
  local table
  if ! table="$(psql_app -Atc "select to_regclass('public.peers');")"; then
    log "ERROR: failed to detect peers table."
    return 15
  fi
  if [[ "$table" != "public.peers" ]]; then
    log "ERROR: required table public.peers not found."
    log "Available tables:"
    if ! psql_app -Atc "select table_schema||'.'||table_name from information_schema.tables where table_type='BASE TABLE' order by 1;"; then
      log "ERROR: failed to list tables."
    fi
    return 11
  fi
  summary_kv "PEERS_TABLE" "$table"

  section "Detect columns"
  if ! COLS="$(psql_app -Atc "select lower(column_name), data_type, udt_name from information_schema.columns where table_schema='public' and table_name='peers' order by ordinal_position;")"; then
    log "ERROR: failed to read columns for public.peers."
    return 16
  fi
  log "COLUMNS(name|type|udt):"
  log "$COLS"

  if ! col_exists "public_key"; then
    log "ERROR: required column public_key not found in public.peers."
    return 12
  fi

  local allowed_expr
  if col_exists "allowed_ips_csv"; then
    allowed_expr="coalesce(allowed_ips_csv::text, '')"
  elif col_exists "allowed_ips"; then
    local dtype udt
    dtype="$(col_type "allowed_ips")"
    udt="$(col_udt "allowed_ips")"
    if [[ "$dtype" == "ARRAY" || "$udt" == _* ]]; then
      allowed_expr="coalesce(array_to_string(allowed_ips, ','), '')"
    else
      allowed_expr="coalesce(allowed_ips::text, '')"
    fi
  else
    log "ERROR: required column allowed_ips or allowed_ips_csv not found."
    return 13
  fi

  local endpoint_expr="''"
  if col_exists "endpoint"; then
    endpoint_expr="coalesce(endpoint::text, '')"
  fi

  local keepalive_expr="''"
  if col_exists "persistent_keepalive"; then
    keepalive_expr="coalesce(nullif(persistent_keepalive::text, '0'), '')"
  fi

  local enabled_expr="1"
  if col_exists "is_enabled"; then
    enabled_expr="case when coalesce(is_enabled::text,'') ~* '^(t|true|1|yes|y)$' then 1 else 0 end"
  elif col_exists "disabled"; then
    enabled_expr="case when coalesce(disabled::text,'') ~* '^(t|true|1|yes|y)$' then 0 else 1 end"
  fi

  local desired_file
  desired_file="$REPORT_DIR/stage35_desired_$(date +'%Y-%m-%d_%H-%M-%S').tsv"

  section "Dump desired peers to TSV"
  if ! psql_app -At -F $'\t' -c "select public_key::text, $allowed_expr, $endpoint_expr, $keepalive_expr, $enabled_expr from public.peers order by public_key;" > "$desired_file"; then
    log "ERROR: failed to dump desired peers."
    return 14
  fi

  local total enabled disabled
  total="$(awk 'NF>0{c++} END{print c+0}' "$desired_file")"
  enabled="$(awk -F'\t' '$5=="1"{c++} END{print c+0}' "$desired_file")"
  disabled="$(awk -F'\t' '$5=="0"{c++} END{print c+0}' "$desired_file")"

  summary_kv "DESIRED_FILE" "$desired_file"
  summary_kv "TOTAL" "$total"
  summary_kv "ENABLED" "$enabled"
  summary_kv "DISABLED" "$disabled"

  update_state "STAGE35_DESIRED_FILE" "$desired_file"
  update_state "STAGE35_DESIRED_REPORT" "$REPORT_FILE"
  update_state "STAGE35_DESIRED_TOTAL" "$total"
  update_state "STAGE35_DESIRED_ENABLED" "$enabled"
  update_state "STAGE35_DESIRED_DISABLED" "$disabled"
  update_state "STAGE35_LAST_TS" "$(date +'%Y-%m-%d_%H-%M-%S')"

  return 0
}

report_init "stage35_desired_db_dump"

rc=0
{
  main
=======
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

source "scripts/lib/report.sh"
source "scripts/lib/appdb.sh"

APP_DB_ENV="${APP_DB_ENV:-$REPO_ROOT/infra/local/app-db.env}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
ts(){ date +"%Y-%m-%d_%H-%M-%S"; }

report_init "stage35_desired_db_dump"
rc=0
{
  section "Stage 3.5 — DESIRED (DB) dump (read-only)"
  out="$OUT_DIR/stage35_desired_$(ts).tsv"

  run_step "Load app DB env" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    echo \"PG_DATABASE=\$PG_DATABASE PG_USER=\$PG_USER\"
  "

  run_step_tee "Export desired TSV from public.\"VpnPeers\" (pub<TAB>allowed<TAB>endpoint<TAB>keepalive<TAB>enabled)" bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'

    psql_app -v ON_ERROR_STOP=1 -Atc \"
      select
        \\\"PublicKey\\\" || E'\\t' ||
        (\\\"AssignedIp\\\" || '/32') || E'\\t' ||
        '' || E'\\t' ||
        '0' || E'\\t' ||
        (case when coalesce(\\\"Status\\\",0) <> 0 then '1' else '0' end)
      from public.\\\"VpnPeers\\\"
      order by \\\"PublicKey\\\";
    \" > '$out'

    wc -l '$out'
  "

  section "Summary"
  log "DESIRED_FILE=$out"
>>>>>>> 68d3b6b (fix)
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
