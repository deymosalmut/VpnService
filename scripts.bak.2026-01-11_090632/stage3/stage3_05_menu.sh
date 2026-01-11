#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
LAST_ENV="${LAST_ENV:-$OUT_DIR/stage35_last_run.env}"
IFACE="${IFACE:-wg1}"

s35_resolve_last_files() {
  local last="/opt/vpn-service/reports/stage35_last_run.env"
  if [[ -z "${DESIRED_FILE:-}" ]]; then
    DESIRED_FILE="$(ls -1t /opt/vpn-service/reports/stage35_desired_*.tsv 2>/dev/null | head -n1 || true)"
  fi
  if [[ -z "${ACTUAL_FILE:-}" ]]; then
    ACTUAL_FILE="$(ls -1t /opt/vpn-service/reports/stage35_actual_*.tsv 2>/dev/null | head -n1 || true)"
  fi
}


mkdir -p "$OUT_DIR"

status_table() {
  # shellcheck disable=SC1090
  [[ -f "$LAST_ENV" ]] && source "$LAST_ENV" || true
  echo
  printf "%-28s | %-11s | %s\n" "STEP" "STATUS" "ARTIFACT"
  echo "--------------------------------------------------------------------------"
  [[ -n "${DESIRED_FILE:-}" && -f "${DESIRED_FILE:-}" ]] && printf "%-28s | %-11s | %s\n" "1_DESIRED_DB" "OK" "$DESIRED_FILE" || printf "%-28s | %-11s |\n" "1_DESIRED_DB" "SKIP"
  [[ -n "${ACTUAL_FILE:-}" && -f "${ACTUAL_FILE:-}" ]] && printf "%-28s | %-11s | %s\n" "2_ACTUAL_WG" "OK" "$ACTUAL_FILE" || printf "%-28s | %-11s |\n" "2_ACTUAL_WG" "SKIP"
  [[ -n "${DIFF_FILE:-}"   && -f "${DIFF_FILE:-}"   ]] && printf "%-28s | %-11s | %s\n" "3_DIFF_PLAN" "OK" "$DIFF_FILE"   || printf "%-28s | %-11s |\n" "3_DIFF_PLAN" "SKIP"
  [[ -n "${LAST_REPORT:-}" && -f "${LAST_REPORT:-}" ]] && printf "%-28s | %-11s | %s\n" "4_APPLY" "OK" "$LAST_REPORT" || printf "%-28s | %-11s |\n" "4_APPLY" "SKIP"
  echo
}

export IFACE OUT_DIR LAST_ENV REPO_ROOT

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
  read -r -p "> " choice

  case "${choice:-}" in
    1)
      bash "$REPO_ROOT/scripts/stage3/stage3_05_desired_db_dump.sh"
      # update env pointer
      last_desired="$(ls -1t "$OUT_DIR"/stage35_desired_*.tsv 2>/dev/null | head -n 1 || true)"
      if [[ -n "$last_desired" ]]; then
        mkdir -p "$OUT_DIR"
        [[ -f "$LAST_ENV" ]] || : >"$LAST_ENV"
        grep -vE '^DESIRED_FILE=' "$LAST_ENV" >"$LAST_ENV.tmp" || true
        { cat "$LAST_ENV.tmp"; echo "DESIRED_FILE=$last_desired"; echo "IFACE=$IFACE"; } >"$LAST_ENV"
        rm -f "$LAST_ENV.tmp"
      fi
      status_table
      ;;
    2)
      bash "$REPO_ROOT/scripts/stage3/stage3_05_actual_wg_dump.sh"
      last_actual="$(ls -1t "$OUT_DIR"/stage35_actual_*.tsv 2>/dev/null | head -n 1 || true)"
      if [[ -n "$last_actual" ]]; then
        [[ -f "$LAST_ENV" ]] || : >"$LAST_ENV"
        grep -vE '^ACTUAL_FILE=' "$LAST_ENV" >"$LAST_ENV.tmp" || true
        { cat "$LAST_ENV.tmp"; echo "ACTUAL_FILE=$last_actual"; echo "IFACE=$IFACE"; } >"$LAST_ENV"
        rm -f "$LAST_ENV.tmp"
      fi
      status_table
      ;;
    3)
      # shellcheck disable=SC1090
      [[ -f "$LAST_ENV" ]] && source "$LAST_ENV" || true
      DESIRED_FILE="${DESIRED_FILE:-}"
      ACTUAL_FILE="${ACTUAL_FILE:-}"
      export DESIRED_FILE ACTUAL_FILE
      s35_resolve_last_files
bash "$REPO_ROOT/scripts/stage3/stage3_05_diff.sh"
      status_table
      ;;
    4)
      bash "$REPO_ROOT/scripts/stage3/stage3_05_reconcile_apply.sh"
      status_table
      ;;
    5)
      bash "$REPO_ROOT/scripts/stage3/stage3_05_desired_db_dump.sh"
      last_desired="$(ls -1t "$OUT_DIR"/stage35_desired_*.tsv 2>/dev/null | head -n 1 || true)"
      [[ -n "$last_desired" ]] && echo "DESIRED_FILE=$last_desired" >"$LAST_ENV"

      bash "$REPO_ROOT/scripts/stage3/stage3_05_actual_wg_dump.sh"
      last_actual="$(ls -1t "$OUT_DIR"/stage35_actual_*.tsv 2>/dev/null | head -n 1 || true)"
      [[ -n "$last_actual" ]] && { cat "$LAST_ENV"; echo "ACTUAL_FILE=$last_actual"; echo "IFACE=$IFACE"; } >"$LAST_ENV.tmp" && mv "$LAST_ENV.tmp" "$LAST_ENV"

      # shellcheck disable=SC1090
      source "$LAST_ENV"
      export DESIRED_FILE ACTUAL_FILE
      bash "$REPO_ROOT/scripts/stage3/stage3_05_diff.sh"
      status_table
      ;;
    9)
      status_table
      ;;
    0)
      exit 0
      ;;
    *)
      echo "Unknown option"
      ;;
  esac
done
