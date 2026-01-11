#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

REPORT_DIR="${REPORT_DIR:-$REPO_ROOT/reports}"
mkdir -p "$REPORT_DIR"
ts(){ date +"%Y-%m-%d_%H-%M-%S"; }
REPORT_FILE="$REPORT_DIR/report_stage34_migrations_locate_$(ts).log"
: >"$REPORT_FILE"

log(){ echo -e "$*" | tee -a "$REPORT_FILE"; }
hr(){ log "----------------------------------------------------------------"; }
section(){ hr; log ">>> $*"; hr; }

main() {
  section "Locate EF migrations artifacts in repo"
  log "REPO_ROOT=$REPO_ROOT"
  log ""

  section "Find *Migration*.cs and *ModelSnapshot*.cs (top 200)"
  (find . -type f \( -name "*Migration*.cs" -o -name "*ModelSnapshot*.cs" \) | sort | head -n 200) | tee -a "$REPORT_FILE" || true

  section "Find directories named Migrations (top 100)"
  (find . -type d -name "Migrations" | sort | head -n 100) | tee -a "$REPORT_FILE" || true

  section "Git status (to see new migration files)"
  (git status --porcelain) | tee -a "$REPORT_FILE" || true

  section "List last 30 modified files under Infrastructure"
  (find ./VpnService.Infrastructure -type f -printf '%TY-%Tm-%Td %TH:%TM %p\n' | sort | tail -n 30) | tee -a "$REPORT_FILE" || true

  section "DONE"
  log "Done. Report saved: $REPORT_FILE"
}

main "$@"
