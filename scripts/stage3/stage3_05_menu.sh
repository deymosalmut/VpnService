#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
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
  esac
done
