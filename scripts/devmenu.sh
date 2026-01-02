#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
CHECKS_DIR="$SCRIPTS_DIR/checks"
LIB_DIR="$SCRIPTS_DIR/lib"

# shellcheck source=/dev/null
source "$LIB_DIR/common.sh"

show_menu() {
  cat <<'EOF'

===============================
 VPN SERVICE — DEV MENU (Ubuntu)
===============================

[0]  Help / Show paths
[1]  Check ENV (OS, dotnet, tools)
[2]  Check Services (postgres, wg-quick, ssh)
[3]  Check WireGuard (wg show, iface, port)
[4]  Check DB connectivity (psql, migrations hint)
[5]  Build (restore + build)
[6]  Run API (foreground)  [Ctrl+C to stop]
[7]  Auth smoke test (login + export TOKEN)
[8]  Admin WG State (GET /api/v1/admin/wg/state)
[9]  Stage 3 E2E (Health -> Login -> Admin WG State)

[a]  Run ALL checks (1..5)
[b]  Run ALL + Stage3 E2E (1..5 + 9)

[q]  Quit

EOF
}

run_step() {
  local script="$1"
  shift || true
  bash "$script" "$@"
}

while true; do
  show_menu
  read -rp "Select: " choice
  case "${choice,,}" in
    0)
      echo "ROOT_DIR=$ROOT_DIR"
      echo "CHECKS_DIR=$CHECKS_DIR"
      ;;
    1) run_step "$CHECKS_DIR/01_env.sh" ;;
    2) run_step "$CHECKS_DIR/02_services.sh" ;;
    3) run_step "$CHECKS_DIR/03_wireguard.sh" ;;
    4) run_step "$CHECKS_DIR/04_db.sh" ;;
    5) run_step "$CHECKS_DIR/05_build.sh" ;;
    6) run_step "$CHECKS_DIR/06_run_api.sh" ;;
    7) run_step "$CHECKS_DIR/07_auth.sh" ;;
    8) run_step "$CHECKS_DIR/08_admin_wg_state.sh" ;;
    9) run_step "$CHECKS_DIR/09_end_to_end_stage3.sh" ;;
    a)
      run_step "$CHECKS_DIR/01_env.sh"
      run_step "$CHECKS_DIR/02_services.sh"
      run_step "$CHECKS_DIR/03_wireguard.sh"
      run_step "$CHECKS_DIR/04_db.sh"
      run_step "$CHECKS_DIR/05_build.sh"
      ;;
    b)
      run_step "$CHECKS_DIR/01_env.sh"
      run_step "$CHECKS_DIR/02_services.sh"
      run_step "$CHECKS_DIR/03_wireguard.sh"
      run_step "$CHECKS_DIR/04_db.sh"
      run_step "$CHECKS_DIR/05_build.sh"
      run_step "$CHECKS_DIR/09_end_to_end_stage3.sh"
      ;;
    q) exit 0 ;;
    *) echo "Unknown option: $choice" ;;
  esac

  echo
  read -rp "Press Enter to continue..." _
done
