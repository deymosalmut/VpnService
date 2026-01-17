#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Stage 3.4 Preflight (A): DB app connect test + migrations precheck
# - diagnosticmenu-style reporting (stdout+stderr+exit code)
# - system/admin DB checks via local socket (sudo -u postgres psql)
# - app DB checks via TCP + password (PGPASSWORD + psql -h/-p)
# - optional commit/push of report (yes/no)
# ============================================================

# ---------- Config (override via env) ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

API_URL="${API_URL:-http://127.0.0.1:5001}"
IFACE="${IFACE:-wg1}"

REPORT_DIR="${REPORT_DIR:-$REPO_ROOT/reports}"
mkdir -p "$REPORT_DIR"

# DB config (APP)
DB_MODE="${DB_MODE:-system}"          # informational; this script uses both admin + app checks
PG_HOST="${PG_HOST:-127.0.0.1}"
PG_PORT="${PG_PORT:-5432}"
PG_DB="${PG_DB:-vpnservice}"
PG_USER="${PG_USER:-vpnservice}"
PG_PASSWORD="${PG_PASSWORD:-}"

# Projects (optional for EF tools)
API_PROJ="${API_PROJ:-$REPO_ROOT/VpnService.Api}"
INFRA_PROJ="${INFRA_PROJ:-$REPO_ROOT/VpnService.Infrastructure}"

# ---------- UI ----------
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ts_utc() { date -u +"%Y-%m-%d_%H-%M-%S"; }
mask_pwd() {
  local v="${1:-}"
  if [[ -z "$v" ]]; then echo "<empty>"; return; fi
  local pfx="${v:0:2}"
  echo "${pfx}***"
}

REPORT_FILE="$REPORT_DIR/report_stage34_preflight_$(ts_utc).log"
touch "$REPORT_FILE"

header() { echo -e "\n${YELLOW}>>> $1${NC}" | tee -a "$REPORT_FILE"; }
ok()     { echo -e "${GREEN}OK${NC} $1" | tee -a "$REPORT_FILE"; }
fail()   { echo -e "${RED}FAIL${NC} $1" | tee -a "$REPORT_FILE"; }

# run_step "Title" cmd...
run_step() {
  local title="$1"; shift
  header "$title"
  echo "CMD: $*" | tee -a "$REPORT_FILE"
  set +e
  "$@" 2>&1 | tee -a "$REPORT_FILE"
  local rc="${PIPESTATUS[0]}"
  set -e
  echo "STATUS: $rc" | tee -a "$REPORT_FILE"
  return "$rc"
}

# run_step_capture VAR "Title" cmd...
run_step_capture() {
  local __var="$1"; shift
  local title="$1"; shift
  header "$title"
  echo "CMD: $*" | tee -a "$REPORT_FILE"
  set +e
  local out
  out="$("$@" 2>&1)"
  local rc=$?
  set -e
  echo "$out" | tee -a "$REPORT_FILE"
  echo "STATUS: $rc" | tee -a "$REPORT_FILE"
  printf -v "$__var" "%s" "$out"
  return "$rc"
}

git_commit_report_yesno() {
  header "Git: commit/push report (yes/no)"
  echo "Report: ${REPORT_FILE#$REPO_ROOT/}" | tee -a "$REPORT_FILE"

  read -r -p "Commit/push this report? (yes/no): " ans
  if [[ "$ans" != "yes" ]]; then
    echo "Skipped git commit/push by user choice." | tee -a "$REPORT_FILE"
    return 0
  fi

  local rel="reports/$(basename "$REPORT_FILE")"
  run_step "Git: add (forced) report only" git -C "$REPO_ROOT" add -f -- "$rel" || true

  # commit only report
  if git -C "$REPO_ROOT" diff --cached --quiet; then
    echo "Nothing staged; skipping commit." | tee -a "$REPORT_FILE"
    return 0
  fi

  run_step "Git: commit report only" git -C "$REPO_ROOT" commit -m "report: stage34 preflight $(basename "$REPORT_FILE")" --only -- "$rel" || true

  # push with rebase fallback
  local branch
  branch="$(git -C "$REPO_ROOT" branch --show-current)"
  if run_step "Git: push" git -C "$REPO_ROOT" push origin "$branch"; then
    ok "Report pushed."
  else
    fail "Push failed; trying pull --rebase + push."
    run_step "Git: pull --rebase" git -C "$REPO_ROOT" pull --rebase origin "$branch" || true
    run_step "Git: push (retry)" git -C "$REPO_ROOT" push origin "$branch" || true
  fi
}

# ---------- Checks ----------
overall_rc=0

header "Stage 3.4 Preflight (A): DB app connect + migrations precheck"
{
  echo "TIME_UTC: $(date -u)"
  echo "HOST: $(hostname)"
  echo "USER: $(whoami)"
  echo "REPO_ROOT: $REPO_ROOT"
  echo "REPORT_FILE: $REPORT_FILE"
  echo
  echo "API_URL: $API_URL"
  echo "IFACE: $IFACE"
  echo
  echo "DB (APP) PG_HOST=$PG_HOST PG_PORT=$PG_PORT PG_DB=$PG_DB PG_USER=$PG_USER PG_PASSWORD=$(mask_pwd "$PG_PASSWORD")"
} | tee -a "$REPORT_FILE"

# 1) API health (non-blocking for DB work)
if run_step "API: health" curl -fsS "$API_URL/health"; then
  ok "API health reachable."
else
  fail "API health failed (non-blocking for DB preflight)."
  overall_rc=1
fi

# 2) WG dump reachable (non-blocking for DB)
if command -v wg >/dev/null 2>&1; then
  run_step "WG: show dump (first 5 lines)" bash -lc "wg show '$IFACE' dump | head -n 5" || overall_rc=1
else
  fail "wg binary not found (non-blocking for DB preflight)."
  overall_rc=1
fi

# 3) DB system/admin check via socket (must not require password)
if run_step "DB (system/socket): select 1" sudo -u postgres psql -v ON_ERROR_STOP=1 -Atc "select 1;"; then
  ok "DB admin socket access OK."
else
  fail "DB admin socket access FAILED. This blocks bootstrap/migrations."
  overall_rc=1
fi

# 4) DB app connect test (TCP + password) - blocks migrations
if [[ -z "$PG_PASSWORD" ]]; then
  fail "PG_PASSWORD is empty; cannot test app connection. Export PG_PASSWORD and rerun."
  overall_rc=1
else
  if run_step "DB (app/tcp): select 1" bash -lc "PGPASSWORD='$PG_PASSWORD' psql -h '$PG_HOST' -p '$PG_PORT' -U '$PG_USER' -d '$PG_DB' -v ON_ERROR_STOP=1 -Atc 'select 1;'"; then
    ok "DB app connection OK."
  else
    fail "DB app connection FAILED (auth/pg_hba/db missing)."
    overall_rc=1
  fi
fi

# 5) EF tools precheck (optional)
if [[ -d "$API_PROJ" ]]; then
  run_step "dotnet: info (top)" bash -lc "dotnet --info | sed -n '1,25p'" || overall_rc=1
else
  fail "API project path not found: $API_PROJ (skipping EF checks)."
  overall_rc=1
fi

# 6) Optional: check dotnet-ef availability
if command -v dotnet-ef >/dev/null 2>&1; then
  ok "dotnet-ef is available."
else
  fail "dotnet-ef not found (install if you plan to run migrations from CLI)."
  # non-blocking: some projects run migrations on startup
fi

# 7) Summarize
header "Summary"
if [[ "$overall_rc" -eq 0 ]]; then
  ok "Stage 3.4 preflight PASSED."
else
  fail "Stage 3.4 preflight FAILED. See report: $REPORT_FILE"
fi

# Offer commit/push on failure
if [[ "$overall_rc" -ne 0 ]]; then
  git_commit_report_yesno || true
fi

echo -e "\nDone. Report saved: $REPORT_FILE"
exit "$overall_rc"
