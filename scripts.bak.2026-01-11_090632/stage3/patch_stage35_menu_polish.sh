#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

python3 - <<'PY'
from pathlib import Path
p = Path("/opt/vpn-service/scripts/stage3/stage3_05_menu.sh")
s = p.read_text(encoding="utf-8", errors="ignore")

# 1) Ensure Run ALL runs desired+actual+diff (and not only 1->3)
s = s.replace('echo "5) Run ALL (1->3)"', 'echo "5) Run ALL (1->2->3)"')

# 2) Improve run_diff parsing to also capture INCOMPLETE_DESIRED if present in report
# We'll just add a line in run_desired to set status WARN when incomplete desired is detected in output.
needle = "if [[ $rc -eq 0 ]]; then set_status \"1_DESIRED_DB\" \"OK\" \"$DESIRED_FILE\"; else set_status \"1_DESIRED_DB\" \"FAIL\" \"${LAST_REPORT:-}\"; fi"
if needle in s:
    s = s.replace(needle, needle + "\n  if echo \"$out\" | grep -q '^INCOMPLETE_DESIRED=YES'; then set_status \"1_DESIRED_DB\" \"WARN\" \"$DESIRED_FILE\"; fi")

p.write_text(s, encoding="utf-8")
print("OK patched:", p)
PY

chmod +x /opt/vpn-service/scripts/stage3/stage3_05_menu.sh
