#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

cat >scripts/stage3/stage3_05_diff.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
IFACE="${IFACE:-wg1}"
cd "$REPO_ROOT"

source "scripts/lib/report.sh"

OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
DESIRED_FILE="${DESIRED_FILE:-}"
ACTUAL_FILE="${ACTUAL_FILE:-}"

report_init "stage35_diff"
rc=0
{
  section "Stage 3.5 — DIFF/PLAN (read-only)"
  [[ -n "$DESIRED_FILE" ]] || DESIRED_FILE="$(ls -1t "$OUT_DIR"/stage35_desired_*.tsv 2>/dev/null | head -n 1 || true)"
  [[ -n "$ACTUAL_FILE"  ]] || ACTUAL_FILE="$(ls -1t "$OUT_DIR"/stage35_actual_*.tsv 2>/dev/null | head -n 1 || true)"

  log "DESIRED_FILE=$DESIRED_FILE"
  log "ACTUAL_FILE=$ACTUAL_FILE"
  [[ -f "$DESIRED_FILE" ]] || { log "FAIL missing desired file"; exit 10; }
  [[ -f "$ACTUAL_FILE"  ]] || { log "FAIL missing actual file"; exit 11; }

  plan_tsv="$OUT_DIR/stage35_plan_$(date +%Y-%m-%d_%H-%M-%S).tsv"
  diff_txt="$OUT_DIR/stage35_diff_$(date +%Y-%m-%d_%H-%M-%S).txt"

  # Determine if desired is incomplete (allowed_ips empty for all rows)
  incomplete="$(awk -F'\t' 'NF>=2{ if($2!="" && $2!=" "){print "NO"; exit} } END{print "YES"}' "$DESIRED_FILE" | tail -n 1)"

  section "Compute plan"
  run_step_tee "plan build (REMOVE-ONLY if desired incomplete)" bash -lc "
    set -Eeuo pipefail
    desired='$DESIRED_FILE'
    actual='$ACTUAL_FILE'
    plan='$plan_tsv'
    diff='$diff_txt'
    incomplete='$incomplete'

    awk -F'\t' 'NF>=1{print \$1}' \"\$desired\" | sed '/^\\s*$/d' | sort -u > /tmp/s35_d_\$\$.txt
    awk -F'\t' 'NF>=1{print \$1}' \"\$actual\"  | sed '/^\\s*$/d' | sort -u > /tmp/s35_a_\$\$.txt

    # Always safe: peers present in WG but absent in DB => REMOVE
    comm -13 /tmp/s35_d_\$\$.txt /tmp/s35_a_\$\$.txt | awk '{print \"REMOVE\\t\"\$1}' > \"\$plan\" || true

    rem=\$(wc -l <\"\$plan\" | tr -d ' ')
    add=0; upd=0; dis=0
    if [[ \"\$incomplete\" == \"YES\" ]]; then
      echo \"SUMMARY remove=\$rem (REMOVE-ONLY mode; desired lacks allowed_ips)\" > \"\$diff\"
      echo \"PLAN_FILE=\$plan\"
      echo \"DIFF_FILE=\$diff\"
      echo \"ADD=\$add REMOVE=\$rem UPDATE=\$upd DISABLE=\$dis TOTAL_CHANGES=\$rem\"
      if [[ \$rem -gt 0 ]]; then echo \"CHANGES_PENDING=YES\"; exit 20; else echo \"CHANGES_PENDING=NO\"; exit 0; fi
    fi

    # If someday desired becomes complete, we’ll extend ADD/UPDATE here.
    echo \"SUMMARY remove=\$rem\" > \"\$diff\"
    echo \"PLAN_FILE=\$plan\"
    echo \"DIFF_FILE=\$diff\"
    echo \"ADD=\$add REMOVE=\$rem UPDATE=\$upd DISABLE=\$dis TOTAL_CHANGES=\$rem\"
    if [[ \$rem -gt 0 ]]; then echo \"CHANGES_PENDING=YES\"; exit 20; else echo \"CHANGES_PENDING=NO\"; exit 0; fi
  " || true

  section "Artifacts"
  log "PLAN_FILE=$plan_tsv"
  log "DIFF_FILE=$diff_txt"
  log "INCOMPLETE_DESIRED=$incomplete"

  pending="$(grep -E 'CHANGES_PENDING=' "$REPORT_FILE" | tail -n 1 | cut -d= -f2 || true)"
  section "Summary"
  if [[ "$pending" == "YES" ]]; then
    log "RESULT=CHANGES_PENDING"
    exit 20
  fi
  log "RESULT=NO_CHANGES"
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
SH

chmod +x scripts/stage3/stage3_05_diff.sh
echo "OK patched: scripts/stage3/stage3_05_diff.sh"
