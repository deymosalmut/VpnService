#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
<<<<<<< HEAD
cd "$REPO_ROOT"

REPORT_DIR="${REPORT_DIR:-$REPO_ROOT/reports}"
export REPORT_DIR

IFACE="${IFACE:-wg1}"
API_URL="${API_URL:-http://localhost:5272}"
export IFACE API_URL
STATE_FILE="$REPORT_DIR/stage35_last_run.env"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

declare -A STEP_LABELS STEP_STATUS STEP_ARTIFACT
STEP_ORDER=("desired" "actual" "diff" "apply")

STEP_LABELS["desired"]="Desired DB dump"
STEP_LABELS["actual"]="Actual WG dump"
STEP_LABELS["diff"]="Diff/Plan"
STEP_LABELS["apply"]="Reconcile APPLY"

STEP_STATUS["desired"]="N/A"
STEP_STATUS["actual"]="N/A"
STEP_STATUS["diff"]="N/A"
STEP_STATUS["apply"]="N/A"

STEP_ARTIFACT["desired"]="-"
STEP_ARTIFACT["actual"]="-"
STEP_ARTIFACT["diff"]="-"
STEP_ARTIFACT["apply"]="-"

REPORTS_WRITABLE=0

color_status() {
  local status="$1"
  case "$status" in
    OK) printf "%sOK%s" "$GREEN" "$NC" ;;
    WARN) printf "%sWARN%s" "$YELLOW" "$NC" ;;
    FAIL) printf "%sFAIL%s" "$RED" "$NC" ;;
    *) printf "%s" "$status" ;;
  esac
}

print_status_table() {
  echo
  echo "STEP | STATUS | ARTIFACT_PATH"
  for key in "${STEP_ORDER[@]}"; do
    local label status artifact
    label="${STEP_LABELS[$key]}"
    status="${STEP_STATUS[$key]:-N/A}"
    artifact="${STEP_ARTIFACT[$key]:--}"
    printf "%s | %s | %s\n" "$label" "$(color_status "$status")" "$artifact"
  done
  echo
  echo "Summary:"
  printf "Desired=%s Actual=%s Diff=%s Apply=%s\n" \
    "$(color_status "${STEP_STATUS[desired]:-N/A}")" \
    "$(color_status "${STEP_STATUS[actual]:-N/A}")" \
    "$(color_status "${STEP_STATUS[diff]:-N/A}")" \
    "$(color_status "${STEP_STATUS[apply]:-N/A}")"
  echo "Legend: OK=GREEN, WARN=YELLOW, FAIL=RED"
  echo
}

load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi
}

ensure_reports_writable() {
  if mkdir -p "$REPORT_DIR" 2>/dev/null; then
    if touch "$REPORT_DIR/.stage35_write_test" 2>/dev/null; then
      rm -f "$REPORT_DIR/.stage35_write_test"
      REPORTS_WRITABLE=1
      return 0
    fi
  fi
  REPORTS_WRITABLE=0
  return 1
}

guard_reports_writable() {
  if ensure_reports_writable; then
    return 0
  fi
  if [[ "$REPORTS_WRITABLE" -ne 1 ]]; then
    echo -e "${RED}FAIL:${NC} reports dir not writable: $REPORT_DIR"
    echo "Hint: run this menu with sudo."
    return 1
  fi
}

ensure_exec_bits() {
  local rc=0 f
  for f in "$REPO_ROOT/scripts/stage3/"*.sh; do
    [[ -e "$f" ]] || continue
    if ! chmod +x "$f" 2>/dev/null; then
      echo -e "${YELLOW}WARN:${NC} chmod +x failed: $f"
      rc=1
    fi
  done
  return "$rc"
}

ask_yes_no() {
  local prompt="$1"
  local ans
  while true; do
    read -r -p "$prompt (yes/no): " ans </dev/tty
    case "${ans,,}" in
      yes|y) return 0 ;;
      no|n) return 1 ;;
      *) echo "Please type yes or no." ;;
    esac
  done
}

run_desired() {
  if ! guard_reports_writable; then
    STEP_STATUS["desired"]="FAIL"
    STEP_ARTIFACT["desired"]="-"
    print_status_table
    return 1
  fi
  local rc=0
  if bash "scripts/stage3/stage3_05_desired_db_dump.sh"; then
    rc=0
  else
    rc=$?
  fi
  load_state
  STEP_ARTIFACT["desired"]="${STAGE35_DESIRED_FILE:-"-"}"
  if [[ "$rc" -eq 0 ]]; then
    STEP_STATUS["desired"]="OK"
  else
    STEP_STATUS["desired"]="FAIL"
  fi
  print_status_table
  return "$rc"
}

run_actual() {
  if ! guard_reports_writable; then
    STEP_STATUS["actual"]="FAIL"
    STEP_ARTIFACT["actual"]="-"
    print_status_table
    return 1
  fi
  local rc=0
  if bash "scripts/stage3/stage3_05_actual_wg_dump.sh"; then
    rc=0
  else
    rc=$?
  fi
  load_state
  STEP_ARTIFACT["actual"]="${STAGE35_ACTUAL_FILE:-"-"}"
  if [[ "$rc" -eq 0 ]]; then
    STEP_STATUS["actual"]="OK"
  else
    STEP_STATUS["actual"]="FAIL"
  fi
  print_status_table
  return "$rc"
}

run_diff() {
  if ! guard_reports_writable; then
    STEP_STATUS["diff"]="FAIL"
    STEP_ARTIFACT["diff"]="-"
    print_status_table
    return 1
  fi
  load_state
  local desired="${STAGE35_DESIRED_FILE:-}"
  local actual="${STAGE35_ACTUAL_FILE:-}"
  local rc=0
  if [[ -n "$desired" && -n "$actual" && -f "$desired" && -f "$actual" ]]; then
    if bash "scripts/stage3/stage3_05_diff.sh" "$desired" "$actual"; then
      rc=0
    else
      rc=$?
    fi
  else
    if bash "scripts/stage3/stage3_05_diff.sh"; then
      rc=0
    else
      rc=$?
    fi
  fi
  load_state
  STEP_ARTIFACT["diff"]="${STAGE35_DIFF_FILE:-"-"}"
  if [[ "$rc" -eq 0 ]]; then
    STEP_STATUS["diff"]="OK"
  elif [[ "$rc" -eq 20 ]]; then
    STEP_STATUS["diff"]="WARN"
  else
    STEP_STATUS["diff"]="FAIL"
  fi
  print_status_table
  return "$rc"
}

run_apply() {
  if ! guard_reports_writable; then
    STEP_STATUS["apply"]="FAIL"
    STEP_ARTIFACT["apply"]="-"
    print_status_table
    return 1
  fi
  local rc=0
  if bash "scripts/stage3/stage3_05_reconcile_apply.sh"; then
    rc=0
  else
    rc=$?
  fi
  load_state
  STEP_ARTIFACT["apply"]="${STAGE35_APPLY_REPORT:-"-"}"
  if [[ "$rc" -eq 0 ]]; then
    STEP_STATUS["apply"]="OK"
  else
    STEP_STATUS["apply"]="FAIL"
  fi
  print_status_table
  return "$rc"
}

run_all() {
  run_desired || return $?
  run_actual || return $?
  run_diff
  local diff_rc=$?
  if [[ "$diff_rc" -eq 20 ]]; then
    if ask_yes_no "Changes pending. Run reconcile APPLY now?"; then
      run_apply || return $?
    fi
    return 20
  fi
  if [[ "$diff_rc" -ne 0 ]]; then
    return "$diff_rc"
  fi
  return 0
}

show_menu() {
  if command -v clear >/dev/null 2>&1; then
    clear
  fi
  echo "================ Stage 3.5 Menu ================"
  echo "Repo root : $REPO_ROOT"
  echo "IFACE     : $IFACE"
  echo "API_URL   : $API_URL"
  echo "Reports   : $REPORT_DIR"
  echo "State     : $STATE_FILE"
  echo "Writable  : $REPORTS_WRITABLE"
  echo "-------------------------------------------------"
  echo "1) Desired DB dump"
  echo "2) Actual WG dump"
  echo "3) Diff/Plan"
  echo "4) Reconcile APPLY"
  echo "5) Run ALL (1->3, then offer 4)"
  echo "0) Exit"
  echo "================================================="
}

if ! ensure_reports_writable; then
  echo -e "${RED}FAIL:${NC} reports dir not writable: $REPORT_DIR"
  echo "Hint: run this menu with sudo."
fi

if ! ensure_exec_bits; then
  echo -e "${YELLOW}WARN:${NC} some scripts may not be executable."
fi

while true; do
  show_menu
  read -r -p "Select: " opt </dev/tty
  case "$opt" in
    1) if ! run_desired; then :; fi ;;
    2) if ! run_actual; then :; fi ;;
    3) if ! run_diff; then :; fi ;;
    4) if ! run_apply; then :; fi ;;
    5) if ! run_all; then :; fi ;;
    0) exit 0 ;;
    *) echo "Invalid choice."; sleep 1 ;;
=======
STAGE3_DIR="$REPO_ROOT/scripts/stage3"
IFACE="${IFACE:-wg1}"

status() {
  if [[ -x "$STAGE3_DIR/stage3_05_status.sh" ]]; then
    echo
    "$STAGE3_DIR/stage3_05_status.sh" || true
    echo
  fi
}

run_step() {
  local name="$1"; shift
  echo
  echo "----------------------------------------------------------------"
  echo ">>> RUN: $name"
  echo "----------------------------------------------------------------"
  "$@"
  echo
}

while true; do
  cat <<MENU
Stage 3.5 Menu (IFACE=$IFACE)
1) Desired DB dump
2) Actual WG dump
3) Diff/Plan
4) Reconcile APPLY
5) Run ALL (1->2->3)
6) Seed 1 DB peer (PublicKey only)
0) Exit
MENU

  read -r -p "> " choice || { echo; echo "EOF - exit"; exit 0; }
  choice="$(printf '%s' "$choice" | tr -d '\r' | xargs || true)"

  case "$choice" in
    1)
      run_step "Desired DB dump" bash "$STAGE3_DIR/stage3_05_desired_db_dump.sh"
      status
      ;;
    2)
      run_step "Actual WG dump" bash "$STAGE3_DIR/stage3_05_actual_wg_dump.sh"
      status
      ;;
    3)
      run_step "Diff/Plan" bash "$STAGE3_DIR/stage3_05_diff.sh"
      status
      ;;
    4)
      run_step "Reconcile APPLY" bash "$STAGE3_DIR/stage3_05_reconcile_apply.sh"
      status
      ;;
    5)
      run_step "Desired DB dump" bash "$STAGE3_DIR/stage3_05_desired_db_dump.sh"
      run_step "Actual WG dump" bash "$STAGE3_DIR/stage3_05_actual_wg_dump.sh"
      run_step "Diff/Plan" bash "$STAGE3_DIR/stage3_05_diff.sh"
      status
      ;;
    6)
      if [[ -x "$STAGE3_DIR/stage3_05_seed_peer_db.sh" ]]; then
        run_step "Seed 1 DB peer" bash "$STAGE3_DIR/stage3_05_seed_peer_db.sh"
      else
        echo "FAIL: $STAGE3_DIR/stage3_05_seed_peer_db.sh not found"
        exit 2
      fi
      status
      ;;
    0|q|quit|exit)
      exit 0
      ;;
    *)
      echo "Unknown option: '$choice'"
      ;;
>>>>>>> 68d3b6b (fix)
  esac
done
