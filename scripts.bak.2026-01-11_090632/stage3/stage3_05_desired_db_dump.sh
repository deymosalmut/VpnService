#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
APP_DB_ENV="${APP_DB_ENV:-$REPO_ROOT/infra/local/app-db.env}"
IFACE="${IFACE:-wg1}"

mkdir -p "$OUT_DIR"
ts(){ date -u +"%Y-%m-%d_%H-%M-%S"; }
OUT="$OUT_DIR/stage35_desired_$(ts).tsv"
REPORT="$OUT_DIR/report_stage35_desired_$(ts).log"

cd "$REPO_ROOT"
source "scripts/lib/appdb.sh"

log(){ echo -e "$*" | tee -a "$REPORT"; }
hr(){ log "----------------------------------------------------------------"; }
section(){ hr; log ">>> $*"; hr; }

: >"$REPORT"

section "Stage 3.5 — DESIRED (DB) dump (read-only)"
log "OUT=$OUT"

section "Load app DB env"
load_app_db_env "$APP_DB_ENV"
log "PG_DATABASE=$PG_DATABASE PG_USER=$PG_USER PG_HOST=$PG_HOST PG_PORT=$PG_PORT PG_PASSWORD=${PG_PASSWORD:+SET}"
log "IFACE=$IFACE"
log ""

section "Export desired rows (pubkey<TAB>allowed<TAB>endpoint<TAB>keepalive<TAB>enabled)"
# Output columns:
# 1 PublicKey (normalized)
# 2 AllowedIps (AssignedIp/32)
# 3 Endpoint (empty)
# 4 Keepalive (0)
# 5 Enabled (Status==1 ? 1 : 0)
#
# Only peers whose VpnServer.Name matches IFACE.
psql_app -v ON_ERROR_STOP=1 -Atc "
with srv as (
  select \"Id\" as server_id
  from public.\"VpnServers\"
  where \"Name\" = '$IFACE'
  limit 1
),
p as (
  select
    pr.\"PublicKey\"::text as public_key,
    pr.\"AssignedIp\"::text as assigned_ip,
    pr.\"Status\"::int as status
  from public.\"VpnPeers\" pr
  join srv on srv.server_id = pr.\"VpnServerId\"
)
select
  public_key || case when right(public_key,1)='=' then '' else '=' end
  || E'\t' ||
  case
    when assigned_ip is null or assigned_ip='' then ''
    when position('/' in assigned_ip)>0 then assigned_ip
    else assigned_ip||'/32'
  end
  || E'\t' || ''                    -- endpoint (desired empty)
  || E'\t' || '0'                   -- keepalive
  || E'\t' || case when status=1 then '1' else '0' end
from p
order by 1;
" | tee "$OUT" >>"$REPORT"
BAD_FORMAT="$(awk -F'\t' 'NF!=5{c++} END{print c+0}' "$OUT")"

  ### S35_NORMALIZE_OUT ###
  # Normalize desired TSV:
  # - ensure 5 columns: pubkey,allowed,endpoint,keepalive,enabled
  # - endpoint: treat 0/(none)/NULL as empty
  # - keepalive: empty -> 0
  # - enabled: empty -> 1
  if [[ -f "$OUT" ]]; then
    tmp="${OUT}.tmp"
    awk -F $'\t' 'BEGIN{OFS="\t"}{
      # pad to 5 columns
      for(i=NF+1;i<=5;i++) $i="";
      # normalize endpoint
      if($3=="0" || $3=="(none)") $3="";
      # normalize keepalive/enabled
      if($4=="") $4="0";
      if($5=="") $5="1";
      print
    }' "$OUT" >"$tmp" && mv -f "$tmp" "$OUT"
  fi

log ""
log "LINES=$LINES"
log "BAD_FORMAT=$BAD_FORMAT"

if [[ "$BAD_FORMAT" -ne 0 ]]; then
  log "WARN: some lines are not 5-column TSV."
fi

section "Summary"
log "DESIRED_FILE=$OUT"
log "Report: $REPORT"


# Robust counts (always based on OUT file)
LINES="$( (sed '/^\s*$/d' "$OUT" | wc -l) | tr -d ' ' )"
echo "LINES=$LINES"

