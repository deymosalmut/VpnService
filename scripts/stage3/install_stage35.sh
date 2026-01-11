#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
STAGE_DIR="$REPO_ROOT/scripts/stage3"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
LAST_ENV="$OUT_DIR/stage35_last_run.env"

mkdir -p "$STAGE_DIR" "$OUT_DIR"

chmod g+s "$OUT_DIR" 2>/dev/null || true

write_file() {
  local path="$1"
  install -m 0755 /dev/null "$path"
  cat >"$path"
  echo "OK wrote: $path"
}

# -----------------------------
# stage3_05_desired_db_dump.sh
# -----------------------------
write_file "$STAGE_DIR/stage3_05_desired_db_dump.sh" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
IFACE="${IFACE:-wg1}"
APP_DB_ENV="${APP_DB_ENV:-$REPO_ROOT/infra/local/app-db.env}"
mkdir -p "$OUT_DIR"
ts(){ date -u +"%Y-%m-%d_%H-%M-%S"; }
T="$(ts)"
REPORT="$OUT_DIR/report_stage35_desired_${T}.log"
OUT="$OUT_DIR/stage35_desired_${T}.tsv"

log(){ echo -e "$*" | tee -a "$REPORT"; }
hr(){ log "----------------------------------------------------------------"; }
section(){ hr; log ">>> $*"; hr; }

: >"$REPORT"

section "Stage 3.5 — DESIRED (DB) dump (read-only)"
log "OUT=$OUT"

section "Load app DB env"
bash -lc "
  set -Eeuo pipefail
  cd '$REPO_ROOT'
  source scripts/lib/appdb.sh
  load_app_db_env '$APP_DB_ENV'
  echo \"PG_DATABASE=\$PG_DATABASE PG_USER=\$PG_USER PG_HOST=\$PG_HOST PG_PORT=\$PG_PORT PG_PASSWORD=\${PG_PASSWORD:+SET}\"
" | tee -a "$REPORT"

# We discovered schema: public."VpnPeers" has "PublicKey" column (required).
section "Export desired pubkeys from public.\"VpnPeers\""
bash -lc "
  set -Eeuo pipefail
  cd '$REPO_ROOT'
  source scripts/lib/appdb.sh
  load_app_db_env '$APP_DB_ENV'
  psql_app -Atc 'select \"PublicKey\" from public.\"VpnPeers\" order by \"CreatedAt\" asc;' \
    | sed '/^\\s*\$/d' \
    | awk -v OFS=\$'\\t' '{print \$1}' \
    > '$OUT'
  wc -l '$OUT'
  head -n 20 '$OUT' || true
" | tee -a "$REPORT"

# Persist last-run env
cat >"$OUT_DIR/stage35_last_run.env" <<ENV
UPDATED_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
IFACE=$IFACE
DESIRED_FILE=$OUT
ACTUAL_FILE=
PLAN_FILE=
DIFF_FILE=
LAST_REPORT=$REPORT
ENV

log ""
section "Summary"
log "DESIRED_FILE=$OUT"
log "Report: $REPORT"
SH

# -----------------------------
# stage3_05_actual_wg_dump.sh
# -----------------------------
write_file "$STAGE_DIR/stage3_05_actual_wg_dump.sh" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
IFACE="${IFACE:-wg1}"
mkdir -p "$OUT_DIR"
ts(){ date -u +"%Y-%m-%d_%H-%M-%S"; }
T="$(ts)"
REPORT="$OUT_DIR/report_stage35_actual_${T}.log"
OUT="$OUT_DIR/stage35_actual_${T}.tsv"

log(){ echo -e "$*" | tee -a "$REPORT"; }
hr(){ log "----------------------------------------------------------------"; }
section(){ hr; log ">>> $*"; hr; }

: >"$REPORT"

section "Stage 3.5 — ACTUAL (WG) dump (read-only)"
log "IFACE=$IFACE"
log "OUT=$OUT"

section "Export actual pubkeys from wg dump (skip interface line)"
bash -lc "
  set -Eeuo pipefail
  wg show '$IFACE' dump \
    | tail -n +2 \
    | awk 'NF>=1{print \$1}' \
    | sed '/^\\s*\$/d' \
    | sort -u \
    > '$OUT'
  wc -l '$OUT'
  head -n 20 '$OUT' || true
" | tee -a "$REPORT"

# Merge into last-run env (preserve desired if exists)
DESIRED_FILE=""
if [[ -f "$OUT_DIR/stage35_last_run.env" ]]; then
  # shellcheck disable=SC1090
  source "$OUT_DIR/stage35_last_run.env" || true
fi

cat >"$OUT_DIR/stage35_last_run.env" <<ENV
UPDATED_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
IFACE=$IFACE
DESIRED_FILE=${DESIRED_FILE:-}
ACTUAL_FILE=$OUT
PLAN_FILE=
DIFF_FILE=
LAST_REPORT=$REPORT
ENV

log ""
section "Summary"
log "ACTUAL_FILE=$OUT"
log "Report: $REPORT"
SH

# -----------------------------
# stage3_05_diff.sh
# -----------------------------
write_file "$STAGE_DIR/stage3_05_diff.sh" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
IFACE="${IFACE:-wg1}"
mkdir -p "$OUT_DIR"

LAST_ENV="$OUT_DIR/stage35_last_run.env"
if [[ ! -f "$LAST_ENV" ]]; then
  echo "FAIL: missing $LAST_ENV (run desired/actual first)"
  exit 2
fi
# shellcheck disable=SC1090
source "$LAST_ENV" || true

ts(){ date -u +"%Y-%m-%d_%H-%M-%S"; }
T="$(ts)"
REPORT="$OUT_DIR/report_stage35_diff_${T}.log"
PLAN="$OUT_DIR/stage35_plan_${T}.tsv"
DIFF="$OUT_DIR/stage35_diff_${T}.txt"

log(){ echo -e "$*" | tee -a "$REPORT"; }
hr(){ log "----------------------------------------------------------------"; }
section(){ hr; log ">>> $*"; hr; }

: >"$REPORT"

section "Stage 3.5 — DIFF/PLAN (read-only)"
log "DESIRED_FILE=${DESIRED_FILE:-}"
log "ACTUAL_FILE=${ACTUAL_FILE:-}"
log "PLAN=$PLAN"
log "DIFF=$DIFF"

if [[ -z "${DESIRED_FILE:-}" || ! -f "${DESIRED_FILE:-}" ]]; then
  log "FAIL missing desired file"
  exit 10
fi
if [[ -z "${ACTUAL_FILE:-}" || ! -f "${ACTUAL_FILE:-}" ]]; then
  log "FAIL missing actual file"
  exit 11
fi

tmpd="$(mktemp -d)"
trap 'rm -rf "$tmpd"' EXIT

DES="$tmpd/desired.txt"
ACT="$tmpd/actual.txt"
ADD="$tmpd/add.txt"
DEL="$tmpd/del.txt"

section "Normalize desired/actual pubkey sets"
bash -lc "
  set -Eeuo pipefail
  sort -u '$DESIRED_FILE' | sed '/^\\s*\$/d' > '$DES'
  sort -u '$ACTUAL_FILE'  | sed '/^\\s*\$/d' > '$ACT'
  echo 'DESIRED_COUNT='\"\$(wc -l <'$DES' | tr -d ' ')\" 
  echo 'ACTUAL_COUNT='\"\$(wc -l <'$ACT' | tr -d ' ')\" 
" | tee -a "$REPORT"

# Plan: ADD = desired - actual ; DEL = actual - desired
comm -23 "$DES" "$ACT" >"$ADD" || true
comm -13 "$DES" "$ACT" >"$DEL" || true

add_n="$(wc -l <"$ADD" | tr -d ' ')"
del_n="$(wc -l <"$DEL" | tr -d ' ')"

: >"$PLAN"
while read -r k; do [[ -n "$k" ]] && printf "ADD\t%s\n" "$k" >>"$PLAN"; done <"$ADD"
while read -r k; do [[ -n "$k" ]] && printf "DEL\t%s\n" "$k" >>"$PLAN"; done <"$DEL"

{
  echo "RESULT=$([[ "$add_n" = "0" && "$del_n" = "0" ]] && echo NO_CHANGES || echo CHANGES_PENDING)"
  echo "ADD=$add_n DEL=$del_n"
  echo "PLAN_FILE=$PLAN"
  echo "DESIRED_FILE=$DESIRED_FILE"
  echo "ACTUAL_FILE=$ACTUAL_FILE"
  echo ""
  echo "PLAN_PREVIEW:"
  head -n 50 "$PLAN" || true
} | tee -a "$DIFF" >/dev/null

section "Summary"
log "RESULT=$([[ "$add_n" = "0" && "$del_n" = "0" ]] && echo NO_CHANGES || echo CHANGES_PENDING)"
log "ADD=$add_n DEL=$del_n"
log "PLAN_FILE=$PLAN"
log "DIFF_FILE=$DIFF"

# Persist last-run env
cat >"$OUT_DIR/stage35_last_run.env" <<ENV
UPDATED_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
IFACE=$IFACE
DESIRED_FILE=$DESIRED_FILE
ACTUAL_FILE=$ACTUAL_FILE
PLAN_FILE=$PLAN
DIFF_FILE=$DIFF
LAST_REPORT=$REPORT
ENV

log ""
section "DONE"
log "Report: $REPORT"
SH

# -----------------------------
# stage3_05_reconcile_apply.sh
# -----------------------------
write_file "$STAGE_DIR/stage3_05_reconcile_apply.sh" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
IFACE="${IFACE:-wg1}"
mkdir -p "$OUT_DIR"

LAST_ENV="$OUT_DIR/stage35_last_run.env"
if [[ ! -f "$LAST_ENV" ]]; then
  echo "FAIL: missing $LAST_ENV (run diff first)"
  exit 2
fi
# shellcheck disable=SC1090
source "$LAST_ENV" || true

ts(){ date -u +"%Y-%m-%d_%H-%M-%S"; }
T="$(ts)"
REPORT="$OUT_DIR/report_stage35_apply_${T}.log"

log(){ echo -e "$*" | tee -a "$REPORT"; }
hr(){ log "----------------------------------------------------------------"; }
section(){ hr; log ">>> $*"; hr; }

: >"$REPORT"

section "Stage 3.5 — RECONCILE APPLY (controlled, local wg set)"
log "IFACE=$IFACE"
log "PLAN_FILE=${PLAN_FILE:-}"

if [[ -z "${PLAN_FILE:-}" || ! -f "${PLAN_FILE:-}" ]]; then
  log "FAIL: missing PLAN_FILE (run diff first)"
  exit 10
fi

ADD="$(grep -c $'^ADD\t' "$PLAN_FILE" 2>/dev/null || true)"
DEL="$(grep -c $'^DEL\t' "$PLAN_FILE" 2>/dev/null || true)"

section "Plan summary"
log "ADD=$ADD DEL=$DEL"
log "Plan preview (top 50):"
head -n 50 "$PLAN_FILE" | tee -a "$REPORT" || true

section "SAFETY GATE"
log "This will APPLY locally via: wg set $IFACE ..."
log "Type APPLY to continue."
read -r -p "> " gate
if [[ "$gate" != "APPLY" ]]; then
  log "Abort: gate not passed."
  exit 30
fi

section "Apply plan to wg interface"
bash -lc "
  set -Eeuo pipefail
  IFACE='$IFACE'
  PLAN='$PLAN_FILE'

  while IFS=\$'\\t' read -r action pub; do
    [[ -z \"\$action\" || -z \"\$pub\" ]] && continue
    case \"\$action\" in
      ADD)
        echo \"[ADD] \$pub\"
        # Minimal: add peer without allowed-ips if unknown. (AllowedIps can be reconciled later)
        wg set \"\$IFACE\" peer \"\$pub\" allowed-ips 0.0.0.0/0
        ;;
      DEL)
        echo \"[DEL] \$pub\"
        wg set \"\$IFACE\" peer \"\$pub\" remove
        ;;
      *)
        echo \"[SKIP] \$action \$pub\"
        ;;
    esac
  done < \"\$PLAN\"
" | tee -a "$REPORT"

section "Post-check: wg show dump (first 10 peer lines)"
bash -lc "
  set -Eeuo pipefail
  wg show '$IFACE' dump | tail -n +2 | head -n 10
" | tee -a "$REPORT"

# Persist last-run env (keep old desired/actual/diff/plan)
cat >"$OUT_DIR/stage35_last_run.env" <<ENV
UPDATED_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
IFACE=$IFACE
DESIRED_FILE=${DESIRED_FILE:-}
ACTUAL_FILE=${ACTUAL_FILE:-}
PLAN_FILE=${PLAN_FILE:-}
DIFF_FILE=${DIFF_FILE:-}
LAST_REPORT=$REPORT
ENV

section "DONE"
log "Report: $REPORT"
SH

# -----------------------------
# stage3_05_status.sh
# -----------------------------
write_file "$STAGE_DIR/stage3_05_status.sh" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
LAST_ENV="$OUT_DIR/stage35_last_run.env"

echo "Stage 3.5 Status"
echo "OUT_DIR=$OUT_DIR"
echo

if [[ ! -f "$LAST_ENV" ]]; then
  echo "No last-run file: $LAST_ENV"
  exit 0
fi

# shellcheck disable=SC1090
source "$LAST_ENV"

echo "UPDATED_UTC=${UPDATED_UTC:-}"
echo "IFACE=${IFACE:-}"
echo "DESIRED_FILE=${DESIRED_FILE:-}"
echo "ACTUAL_FILE=${ACTUAL_FILE:-}"
echo "PLAN_FILE=${PLAN_FILE:-}"
echo "DIFF_FILE=${DIFF_FILE:-}"
echo "LAST_REPORT=${LAST_REPORT:-}"
echo

stat_line() {
  local name="$1" file="$2"
  if [[ -z "${file:-}" ]]; then
    printf "%-14s: %s\n" "$name" "MISSING"
    return
  fi
  if [[ ! -f "$file" ]]; then
    printf "%-14s: %s %s\n" "$name" "MISSING" "$file"
    return
  fi
  local n
  n="$(wc -l <"$file" | tr -d ' ')"
  printf "%-14s: OK (%s lines) %s\n" "$name" "$n" "$file"
}

stat_line "DESIRED" "${DESIRED_FILE:-}"
stat_line "ACTUAL"  "${ACTUAL_FILE:-}"
stat_line "PLAN"    "${PLAN_FILE:-}"
stat_line "DIFF"    "${DIFF_FILE:-}"
SH

# -----------------------------
# stage3_05_menu.sh
# -----------------------------
write_file "$STAGE_DIR/stage3_05_menu.sh" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
IFACE="${IFACE:-wg1}"
export REPO_ROOT IFACE

S="$REPO_ROOT/scripts/stage3"
STATUS_FILE="$S/stage3_05_status.sh"

run_desired(){ bash "$S/stage3_05_desired_db_dump.sh"; }
run_actual(){ bash "$S/stage3_05_actual_wg_dump.sh"; }
run_diff(){ bash "$S/stage3_05_diff.sh"; }
run_apply(){ bash "$S/stage3_05_reconcile_apply.sh"; }

while true; do
  echo
  echo "Stage 3.5 Menu (IFACE=$IFACE)"
  echo "1) Desired DB dump"
  echo "2) Actual WG dump"
  echo "3) Diff/Plan"
  echo "4) Reconcile APPLY (local wg set)"
  echo "5) Run ALL (1->2->3)"
  echo "9) Status"
  echo "0) Exit"
  echo
  read -r -p "> " choice || true

  case "$choice" in
    1) run_desired ;;
    2) run_actual ;;
    3) run_diff ;;
    4) run_apply ;;
    5) run_desired; run_actual; run_diff ;;
    9) bash "$STATUS_FILE" ;;
    0) exit 0 ;;
    *) echo "Unknown option" ;;
  esac
done
SH

echo
echo "OK Stage 3.5 installed."
echo "Run: bash $STAGE_DIR/stage3_05_menu.sh"
