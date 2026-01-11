#!/usr/bin/env bash
set -Eeuo pipefail

# -----------------------------
# Reporting primitives
# -----------------------------
REPORT_DIR="${REPORT_DIR:-/opt/vpn-service/reports}"
mkdir -p "$REPORT_DIR"

_ts() { date +"%Y-%m-%d_%H-%M-%S"; }

report_init() {
  local name="$1"
  REPORT_FILE="${REPORT_FILE:-$REPORT_DIR/report_${name}_$(_ts).log}"
  : > "$REPORT_FILE"
  export REPORT_FILE
}

log() { echo -e "$*" | tee -a "$REPORT_FILE"; }

hr() { log "----------------------------------------------------------------"; }

section() {
  hr
  log ">>> $*"
  hr
}

# Run a command, log stdout/stderr + exit code; fail hard on non-zero
run_step() {
  local title="$1"; shift
  section "$title"
  log "+ CMD: $*"
  set +e
  ( "$@" ) >>"$REPORT_FILE" 2>&1
  local rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    log "STATUS: OK (exit=$rc)"
  else
    log "STATUS: FAIL (exit=$rc)"
    return $rc
  fi
}

# Same, but also echoes command output to console live
run_step_tee() {
  local title="$1"; shift
  section "$title"
  log "+ CMD: $*"
  set +e
  ( "$@" ) 2>&1 | tee -a "$REPORT_FILE"
  local rc=${PIPESTATUS[0]}
  set -e
  if [[ $rc -eq 0 ]]; then
    log "STATUS: OK (exit=$rc)"
  else
    log "STATUS: FAIL (exit=$rc)"
    return $rc
  fi
}

summary_kv() {
  log "SUMMARY: $1=$2"
}

maybe_commit_report_on_fail() {
  local rc="$1"
  if [[ $rc -eq 0 ]]; then
    return 0
  fi

  hr
  log "FAIL detected. Report: $REPORT_FILE"
  read -r -p "Commit report to git? (yes/no): " ans
  if [[ "${ans,,}" == "yes" ]]; then
    # add -f to bypass gitignore for reports/
    git add -f "$REPORT_FILE" >/dev/null 2>&1 || true
    git commit -m "report: $(basename "$REPORT_FILE")" >/dev/null 2>&1 || true
    log "Report committed."
  else
    log "Report NOT committed."
  fi
}

maybe_commit_report_always() {
  hr
  log "Report: $REPORT_FILE"
  read -r -p "Commit report to git? (yes/no): " ans
  if [[ "${ans,,}" == "yes" ]]; then
    git add -f "$REPORT_FILE" >/dev/null 2>&1 || true
    git commit -m "report: $(basename "$REPORT_FILE")" >/dev/null 2>&1 || true
    log "Report committed."
  else
    log "Report NOT committed."
  fi
}
