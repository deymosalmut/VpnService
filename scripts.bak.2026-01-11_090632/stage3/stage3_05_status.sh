#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"

# Safe load KEY=VALUE from last-run env (do NOT source)
load_kv_env() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[A-Z0-9_]+= ]] || continue
    local k="${line%%=*}"
    local v="${line#*=}"
    # strip possible CR
    v="${v%$'\r'}"
    printf -v "$k" '%s' "$v"
  done < "$f"
}

LAST_ENV="$OUT_DIR/stage35_last_run.env"
load_kv_env "$LAST_ENV"
IFACE="${IFACE:-wg1}"

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
