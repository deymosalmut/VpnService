#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
STATE_FILE="$OUT_DIR/stage35_last_run.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo "Stage 3.5 Status"
echo "OUT_DIR=$OUT_DIR"
echo

if [[ ! -f "$STATE_FILE" ]]; then
  echo -e "${YELLOW}WARN${NC}: no state file yet: $STATE_FILE"
  exit 0
fi

# Safe env reader: only accept KEY=VALUE lines, strip surrounding quotes
getv() {
  local key="$1"
  local line
  line="$(grep -E "^${key}=" "$STATE_FILE" | tail -n 1 || true)"
  [[ -n "$line" ]] || { echo ""; return 0; }
  local val="${line#*=}"
  val="${val%$'\r'}"
  # strip optional single/double quotes
  if [[ "$val" == \"*\" && "$val" == *\" ]]; then val="${val:1:-1}"; fi
  if [[ "$val" == \'*\' && "$val" == *\' ]]; then val="${val:1:-1}"; fi
  echo "$val"
}

UPDATED_UTC="$(getv UPDATED_UTC)"
IFACE="$(getv IFACE)"
DESIRED_FILE="$(getv DESIRED_FILE)"
ACTUAL_FILE="$(getv ACTUAL_FILE)"
PLAN_FILE="$(getv PLAN_FILE)"
DIFF_FILE="$(getv DIFF_FILE)"
LAST_REPORT="$(getv LAST_REPORT)"

echo "UPDATED_UTC=${UPDATED_UTC}"
echo "IFACE=${IFACE}"
echo "DESIRED_FILE=${DESIRED_FILE}"
echo "ACTUAL_FILE=${ACTUAL_FILE}"
echo "PLAN_FILE=${PLAN_FILE}"
echo "DIFF_FILE=${DIFF_FILE}"
echo "LAST_REPORT=${LAST_REPORT}"
echo

chk(){
  local label="$1" path="$2"
  if [[ -z "$path" ]]; then
    printf "%-14s : %b%s%b\n" "$label" "$YELLOW" "MISSING" "$NC"
    return
  fi
  if [[ -f "$path" ]]; then
    local n
    n="$(wc -l <"$path" 2>/dev/null | tr -d ' ' || echo "?")"
    printf "%-14s : %b%s%b (%s lines) %s\n" "$label" "$GREEN" "OK" "$NC" "$n" "$path"
  else
    printf "%-14s : %b%s%b %s\n" "$label" "$RED" "FAIL" "$NC" "$path"
  fi
}

chk "DESIRED" "$DESIRED_FILE"
chk "ACTUAL"  "$ACTUAL_FILE"
chk "PLAN"    "$PLAN_FILE"
chk "DIFF"    "$DIFF_FILE"
