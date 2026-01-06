#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

# ---- report helpers (используем твой подход: лог + commit report on fail) ----
REPORT_DIR="${REPORT_DIR:-$REPO_ROOT/reports}"
mkdir -p "$REPORT_DIR"
ts(){ date +"%Y-%m-%d_%H-%M-%S"; }
REPORT_FILE="$REPORT_DIR/report_dotnet_ef_fix_$(ts).log"
: >"$REPORT_FILE"

log(){ echo -e "$*" | tee -a "$REPORT_FILE"; }
hr(){ log "----------------------------------------------------------------"; }
section(){ hr; log ">>> $*"; hr; }

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
  fi
  return $rc
}

maybe_commit_report_on_fail() {
  local rc="$1"
  if [[ $rc -eq 0 ]]; then
    log "Done. Report: $REPORT_FILE"
    exit 0
  fi

  hr
  log "FAIL detected. Report: $REPORT_FILE"
  read -r -p "Commit report to git? (yes/no): " ans
  if [[ "${ans,,}" == "yes" ]]; then
    git add -f "$REPORT_FILE" >/dev/null 2>&1 || true
    git commit -m "report: $(basename "$REPORT_FILE")" >/dev/null 2>&1 || true
    log "Report committed."
  else
    log "Report NOT committed."
  fi
  exit "$rc"
}

# ---- helpers ----
detect_ef_major_minor() {
  # Ищем версию EF в csproj'ах: EntityFrameworkCore.Design / Npgsql.EntityFrameworkCore.PostgreSQL
  # Возвращаем "8.0" или "9.0". Если не нашли — default 8.0.
  local v
  v="$(grep -R --line-number -E 'Microsoft\.EntityFrameworkCore\.Design|Microsoft\.EntityFrameworkCore\b|Npgsql\.EntityFrameworkCore\.PostgreSQL' -n ./*.sln . 2>/dev/null \
    | sed -n 's/.*Version="\([0-9]\+\)\.\([0-9]\+\)\..*".*/\1.\2/p' \
    | head -n 1 || true)"
  if [[ -n "$v" ]]; then
    echo "$v"
  else
    echo "8.0"
  fi
}

ensure_nuget_org_source() {
  # Добавляем nuget.org если его нет
  if dotnet nuget list source | grep -qiE 'nuget\.org'; then
    return 0
  fi
  dotnet nuget add source "https://api.nuget.org/v3/index.json" -n "nuget.org"
}

disable_suspicious_local_sources() {
  # Если есть источники вида file:// или локальные каталоги — не трогаем автоматически.
  # Но если есть явно битый источник с именем "tools" или "local" — просто логируем.
  dotnet nuget list source || true
}

# ---- main ----
rc=0

{
  section "dotnet info"
  run_step_tee "dotnet --info (head)" bash -lc "dotnet --info | sed -n '1,80p'"

  section "nuget sources"
  run_step_tee "dotnet nuget list source" bash -lc "dotnet nuget list source"

  # Обязательное условие: доступен nuget.org
  run_step_tee "Ensure nuget.org source exists" bash -lc "ensure_nuget_org_source() { \
      if dotnet nuget list source | grep -qiE 'nuget\\.org'; then exit 0; fi; \
      dotnet nuget add source 'https://api.nuget.org/v3/index.json' -n 'nuget.org'; \
    }; ensure_nuget_org_source"

  # Чистим кэш NuGet — часто решает ошибку с кривыми пакетами/метаданными
  run_step_tee "dotnet nuget locals all --clear" bash -lc "dotnet nuget locals all --clear"

  section "tool-manifest (local tool)"
  run_step_tee "Create tool-manifest if missing" bash -lc "
    cd '$REPO_ROOT'
    if [[ -f .config/dotnet-tools.json ]]; then
      echo 'Tool-manifest exists: .config/dotnet-tools.json'
      exit 0
    fi
    dotnet new tool-manifest
  "

  EF_MM="$(detect_ef_major_minor)"
  log "Detected EF major.minor: $EF_MM"

  # Выбираем безопасный диапазон версий dotnet-ef:
  # - если EF 9.0 -> ставим 9.*
  # - иначе -> 8.*
  TOOL_RANGE="$EF_MM.*"
  log "Will install dotnet-ef version: $TOOL_RANGE (local tool)"

  section "install/restore dotnet-ef"
  # Сначала пробуем install с диапазоном. Если диапазон не проходит, fallback на конкретные LTS-версии.
  run_step_tee "dotnet tool install dotnet-ef --version $TOOL_RANGE" bash -lc "
    cd '$REPO_ROOT'
    dotnet tool install dotnet-ef --version '$TOOL_RANGE' || exit 11
  " || {
    log "Install with range failed. Trying fallbacks..."
    # Fallbacks (не требует web поиска; типовые стабильные)
    # Если EF_MM=9.0 -> пробуем 9.0.0, иначе 8.0.0
    if [[ "$EF_MM" == "9.0" ]]; then
      run_step_tee "Fallback install dotnet-ef --version 9.0.0" bash -lc "cd '$REPO_ROOT' && dotnet tool install dotnet-ef --version 9.0.0" || rc=$?
    else
      run_step_tee "Fallback install dotnet-ef --version 8.0.0" bash -lc "cd '$REPO_ROOT' && dotnet tool install dotnet-ef --version 8.0.0" || rc=$?
    fi
  }

  # Restore (если уже был установлен / или частично)
  run_step_tee "dotnet tool restore" bash -lc "cd '$REPO_ROOT' && dotnet tool restore"

  section "verify"
  run_step_tee "dotnet ef --version" bash -lc "cd '$REPO_ROOT' && dotnet ef --version"
  run_step_tee "dotnet ef --help (smoke)" bash -lc "cd '$REPO_ROOT' && dotnet ef --help | head -n 20"

} || rc=$?

maybe_commit_report_on_fail "$rc"
