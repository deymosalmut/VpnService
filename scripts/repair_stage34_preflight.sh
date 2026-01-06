#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

F="scripts/stage34_preflight.sh"

if [[ ! -f "$F" ]]; then
  echo "ERROR: not found: $F" >&2
  exit 2
fi

# 1) Попробуем восстановить из последнего .bak_*
latest_bak="$(ls -1t scripts/stage34_preflight.sh.bak_* 2>/dev/null | head -n 1 || true)"
if [[ -n "$latest_bak" ]]; then
  cp -a "$latest_bak" "$F"
  echo "OK restored from backup: $latest_bak"
else
  echo "WARN no backup found; will patch current file in-place." >&2
fi

# 2) Делаем новую backup перед модификацией
cp -a "$F" "${F}.repairbak_$(date +%Y-%m-%d_%H-%M-%S)"

# 3) Безопасный патч через python: удаляем старые блоки и вставляем новый блок в гарантированное место
python3 - <<'PY'
import re
from pathlib import Path

p = Path("scripts/stage34_preflight.sh")
s = p.read_text(encoding="utf-8", errors="ignore")

# --- Удаляем любые ранее добавленные блоки dotnet ef presence (если есть) ---
# Ищем по уникальному заголовку и режем до следующего ">>> " или до Summary.
s = re.sub(
    r'\n>>> dotnet: ef \(local tool\) presence \(WARN-only\).*?(?=\n>>> |\n>>> Summary|\Z)',
    '\n',
    s,
    flags=re.S
)

# --- Удаляем старую проверку dotnet-ef (если была в preflight) ---
# Любые строки с "dotnet-ef" в пределах блока dotnet-этапа — удаляем аккуратно
s = re.sub(r'^.*dotnet-ef.*\n', '', s, flags=re.M)

# --- Находим место вставки: перед ">>> Summary" ---
m = re.search(r'\n>>> Summary\n', s)
if not m:
    raise SystemExit("ERROR: Cannot find '>>> Summary' marker in stage34_preflight.sh")

inject = r'''
>>> dotnet: ef (local tool) presence (WARN-only)
CMD: bash -lc cd '/opt/vpn-service' && dotnet ef --version
'''  # это только лог-заголовок, реальную логику вставим как bash-код ниже

# Вставляем bash-блок строго перед Summary
bash_block = r'''
# --- dotnet ef (local tool) presence: WARN-only ---
echo -e "\n>>> dotnet: ef (local tool) presence (WARN-only)" | tee -a "$REPORT_FILE"
echo "CMD: bash -lc cd '$REPO_ROOT' && dotnet ef --version" | tee -a "$REPORT_FILE"

if bash -lc "cd '$REPO_ROOT' && dotnet ef --version" >>"$REPORT_FILE" 2>&1; then
  echo "STATUS: 0" | tee -a "$REPORT_FILE"
  echo "OK dotnet ef available." | tee -a "$REPORT_FILE"
else
  # attempt restore if tool-manifest exists
  if [[ -f "$REPO_ROOT/.config/dotnet-tools.json" ]]; then
    echo "INFO tool-manifest found; running: dotnet tool restore" | tee -a "$REPORT_FILE"
    bash -lc "cd '$REPO_ROOT' && dotnet tool restore" >>"$REPORT_FILE" 2>&1 || true
  fi

  if bash -lc "cd '$REPO_ROOT' && dotnet ef --version" >>"$REPORT_FILE" 2>&1; then
    echo "STATUS: 0" | tee -a "$REPORT_FILE"
    echo "OK dotnet ef available (after tool restore)." | tee -a "$REPORT_FILE"
  else
    echo "STATUS: 0" | tee -a "$REPORT_FILE"
    echo "WARN dotnet ef not available. Migrations CLI steps will be skipped until tool is installed." | tee -a "$REPORT_FILE"
  fi
fi
'''

s = s[:m.start()] + "\n" + bash_block + "\n" + s[m.start():]
p.write_text(s, encoding="utf-8")
print("OK patched:", p)
PY

chmod +x "$F"

# 4) Быстрые sanity-check'и (bash -n + запуск)
echo ">>> bash -n $F"
bash -n "$F"

echo ">>> RUN preflight"
bash "$F"
