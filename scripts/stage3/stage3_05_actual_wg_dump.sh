#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
IFACE="${IFACE:-wg1}"
cd "$REPO_ROOT"

source "scripts/lib/report.sh"

OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"

report_init "stage35_actual_wg_dump"
rc=0
{
  section "Stage 3.5 — ACTUAL (WG) dump (read-only)"

  out="$OUT_DIR/stage35_actual_$(date +%Y-%m-%d_%H-%M-%S).tsv"
  section "Export actual TSV (pub<TAB>allowed<TAB>endpoint<TAB>keepalive<TAB>enabled=1)"
  log "OUT=$out"

  run_step_tee "wg dump -> tsv" bash -lc "
    set -Eeuo pipefail
    wg show '$IFACE' dump | tail -n +2 | awk -v OFS=\$'\\t' 'NF>=5{print \$1,\$4,\$3,\$5,1}' > '$out'
    wc -l '$out'
  "

  section "Summary"
  log "ACTUAL_FILE=$out"
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
