#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

REPORT_DIR="$REPO_ROOT/reports"
MODE="${MODE:-code}"   # code | report | none
REPORT_FILE_TO_COMMIT="${REPORT_FILE_TO_COMMIT:-}"

echo ">>> git hygiene (stage34)"
echo "REPO_ROOT=$REPO_ROOT"
echo "MODE=$MODE"
echo

echo ">>> Current git status (porcelain)"
git status --porcelain || true
echo

echo ">>> Removing transient files (safe)"
rm -f "$REPORT_DIR/api.pid" 2>/dev/null || true
rm -f "$REPORT_DIR/"*.api.out 2>/dev/null || true
echo "OK removed: reports/api.pid + *.api.out (if existed)"
echo

echo ">>> SAFETY GATE"
echo "This may stage/commit changes depending on MODE."
echo "Type RUN to continue."
read -r -p "> " gate
if [[ "$gate" != "RUN" ]]; then
  echo "Abort."
  exit 30
fi

case "$MODE" in
  none)
    echo "MODE=none: no commit, only cleanup done."
    git status --porcelain || true
    exit 0
    ;;
  report)
    if [[ -z "$REPORT_FILE_TO_COMMIT" ]]; then
      echo "ERROR: MODE=report requires REPORT_FILE_TO_COMMIT=/opt/vpn-service/reports/..."
      exit 40
    fi
    if [[ ! -f "$REPORT_FILE_TO_COMMIT" ]]; then
      echo "ERROR: report file not found: $REPORT_FILE_TO_COMMIT"
      exit 41
    fi
    echo ">>> Commit only report file"
    git add -f "$REPORT_FILE_TO_COMMIT"
    git commit -m "report: $(basename "$REPORT_FILE_TO_COMMIT")" || true
    ;;
  code)
    echo ">>> Commit code changes (exclude reports/, infra/local/, obj/bin)"
    # Stage only tracked changes outside reports/
    # 1) stage updates to tracked files, excluding reports/*
    git add -u ':!reports/*' ':!infra/local/*' || true

    # 2) stage new relevant files explicitly (factory, scripts)
    [[ -f VpnService.Infrastructure/Persistence/VpnDbContextFactory.cs ]] && git add VpnService.Infrastructure/Persistence/VpnDbContextFactory.cs || true

    # scripts new files
    git add scripts/stage3/stage3_04_migrations_check.sh scripts/stage3/stage3_04_migrations_apply.sh 2>/dev/null || true
    git add scripts/stage3/stage3_04_ef_fix_design_time.sh scripts/stage3/stage3_04_migrations_create_initial.sh 2>/dev/null || true
    git add scripts/git_hygiene_stage34.sh 2>/dev/null || true

    echo
    echo ">>> Staged diff (name-only)"
    git diff --cached --name-only || true
    echo
    echo "Type COMMIT to commit staged changes."
    read -r -p "> " gate2
    if [[ "$gate2" != "COMMIT" ]]; then
      echo "Abort commit; leaving index staged."
      exit 50
    fi
    git commit -m "stage34: ef design-time + migrations scripts" || true
    ;;
  *)
    echo "ERROR: unknown MODE=$MODE (use code|report|none)"
    exit 60
    ;;
esac

echo
echo ">>> Done. Final status:"
git status --porcelain || true
