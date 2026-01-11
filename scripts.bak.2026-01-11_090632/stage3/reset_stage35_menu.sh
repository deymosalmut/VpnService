#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
IFACE="${IFACE:-wg1}"
cd "$REPO_ROOT"

cat >scripts/stage3/stage3_05_menu.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
IFACE="${IFACE:-wg1}"
cd "$REPO_ROOT"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
STATE_FILE="$OUT_DIR/stage35_last_run.env"
mkdir -p "$OUT_DIR"

# colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
c_status() {
  local st="$1"
  case "$st" in
    OK)   echo -e "${GREEN}OK${NC}" ;;
    WARN) echo -e "${YELLOW}WARN${NC}" ;;
    FAIL) echo -e "${RED}FAIL${NC}" ;;
    SKIP) echo -e "${YELLOW}SKIP${NC}" ;;
    *)    echo "$st" ;;
  esac
}

# step state
declare -A S_STATUS
declare -A S_ART

set_status() { S_STATUS["$1"]="$2"; S_ART["$1"]="${3:-}"; }

save_state() {
  {
    echo "UPDATED_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "IFACE=$IFACE"
    echo "DESIRED_FILE=${DESIRED_FILE:-}"
    echo "ACTUAL_FILE=${ACTUAL_FILE:-}"
    echo "PLAN_FILE=${PLAN_FILE:-}"
    echo "DIFF_FILE=${DIFF_FILE:-}"
    echo "LAST_REPORT=${LAST_REPORT:-}"
  } >"$STATE_FILE"
}

load_state() {
  DESIRED_FILE=""; ACTUAL_FILE=""; PLAN_FILE=""; DIFF_FILE=""; LAST_REPORT=""
  [[ -f "$STATE_FILE" ]] || return 0
  # safe parse KEY=VALUE only
  while IFS= read -r ln; do
    [[ "$ln" =~ ^[A-Z0-9_]+= ]] || continue
    key="${ln%%=*}"; val="${ln#*=}"
    case "$key" in
      DESIRED_FILE) DESIRED_FILE="$val" ;;
      ACTUAL_FILE)  ACTUAL_FILE="$val" ;;
      PLAN_FILE)    PLAN_FILE="$val" ;;
      DIFF_FILE)    DIFF_FILE="$val" ;;
      LAST_REPORT)  LAST_REPORT="$val" ;;
    esac
  done <"$STATE_FILE"
}

print_table() {
  echo
  printf "%-28s | %-12s | %s\n" "STEP" "STATUS" "ARTIFACT"
  echo "--------------------------------------------------------------------------"
  for k in 1_DESIRED_DB 2_ACTUAL_WG 3_DIFF_PLAN 4_APPLY; do
    local st="${S_STATUS[$k]:-SKIP}"
    local art="${S_ART[$k]:-}"
    printf "%-28s | %-12b | %s\n" "$k" "$(c_status "$st")" "$art"
  done
  echo
}

run_desired() {
  local out rc
  out="$(bash "$DIR/stage3_05_desired_db_dump.sh" 2>&1)"; rc=$?
  echo "$out"
  DESIRED_FILE="$(echo "$out" | awk -F= '/^DESIRED_FILE=/{print $2}' | tail -n 1)"
  LAST_REPORT="$(echo "$out" | awk -F': ' '/^Done\. Report saved:/{print $2}' | tail -n 1)"
  if [[ $rc -eq 0 ]]; then
    set_status "1_DESIRED_DB" "OK" "$DESIRED_FILE"
    if echo "$out" | grep -q '^INCOMPLETE_DESIRED=YES'; then set_status "1_DESIRED_DB" "WARN" "$DESIRED_FILE"; fi
  else
    set_status "1_DESIRED_DB" "FAIL" "${LAST_REPORT:-}"
  fi
  save_state
}

run_actual() {
  local out rc
  out="$(bash "$DIR/stage3_05_actual_wg_dump.sh" 2>&1)"; rc=$?
  echo "$out"
  ACTUAL_FILE="$(echo "$out" | awk -F= '/^ACTUAL_FILE=/{print $2}' | tail -n 1)"
  LAST_REPORT="$(echo "$out" | awk -F': ' '/^Done\. Report saved:/{print $2}' | tail -n 1)"
  if [[ $rc -eq 0 ]]; then set_status "2_ACTUAL_WG" "OK" "$ACTUAL_FILE"; else set_status "2_ACTUAL_WG" "FAIL" "${LAST_REPORT:-}"; fi
  save_state
}

run_diff() {
  local out rc
  out="$(DESIRED_FILE="${DESIRED_FILE:-}" ACTUAL_FILE="${ACTUAL_FILE:-}" bash "$DIR/stage3_05_diff.sh" 2>&1)"; rc=$?
  echo "$out"
  PLAN_FILE="$(echo "$out" | awk -F= '/^PLAN_FILE=/{print $2}' | tail -n 1)"
  DIFF_FILE="$(echo "$out" | awk -F= '/^DIFF_FILE=/{print $2}' | tail -n 1)"
  LAST_REPORT="$(echo "$out" | awk -F': ' '/^Done\. Report saved:/{print $2}' | tail -n 1)"
  if [[ $rc -eq 0 ]]; then set_status "3_DIFF_PLAN" "OK" "$DIFF_FILE"
  else set_status "3_DIFF_PLAN" "FAIL" "$DIFF_FILE"
  fi
  save_state
}

run_apply() {
  local out rc
  out="$(PLAN_FILE="${PLAN_FILE:-}" bash "$DIR/stage3_05_reconcile_apply.sh" 2>&1)"; rc=$?
  echo "$out"
  LAST_REPORT="$(echo "$out" | awk -F': ' '/^Done\. Report saved:/{print $2}' | tail -n 1)"
  if [[ $rc -eq 0 ]]; then set_status "4_APPLY" "OK" "${LAST_REPORT:-}"
  else set_status "4_APPLY" "FAIL" "${LAST_REPORT:-}"
  fi
  save_state
}

run_seed() {
  local out rc
  out="$(bash "$DIR/stage3_05_seed_peer_db.sh" 2>&1)"; rc=$?
  echo "$out"
  LAST_REPORT="$(echo "$out" | awk -F': ' '/^Done\. Report saved:/{print $2}' | tail -n 1)"
  if [[ $rc -eq 0 ]]; then
    # no dedicated step line; just keep last report
    :
  fi
  save_state
}

run_all() {
  run_desired || true
  run_actual || true
  run_diff || true
}

main() {
  load_state
  while true; do
    echo "Stage 3.5 Menu (IFACE=$IFACE)"
    echo "1) Desired DB dump"
    echo "2) Actual WG dump"
    echo "3) Diff/Plan"
    echo "4) Reconcile APPLY"
    echo "5) Run ALL (1->2->3)"
    echo "6) Seed 1 DB peer (PublicKey only)"
    echo "0) Exit"
    echo
    read -r -p "> " choice

    case "$choice" in
      1) run_desired; print_table ;;
      2) run_actual;  print_table ;;
      3) run_diff;    print_table ;;
      4) run_apply;   print_table ;;
      5) run_all;     print_table ;;
      6) run_seed;    print_table ;;
      0) exit 0 ;;
      *) echo "Unknown option" ;;
    esac
  done
}

main "$@"
SH

chmod +x scripts/stage3/stage3_05_menu.sh
echo "OK reset: scripts/stage3/stage3_05_menu.sh"
