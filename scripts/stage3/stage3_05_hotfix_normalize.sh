#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

echo "[*] Hotfix Stage 3.5: normalize endpoint/fields for desired+actual+diff"

patch_file() {
  local f="$1"
  [[ -f "$f" ]] || { echo "FAIL: missing $f"; exit 1; }
}

patch_file scripts/stage3/stage3_05_desired_db_dump.sh
patch_file scripts/stage3/stage3_05_actual_wg_dump.sh
patch_file scripts/stage3/stage3_05_diff.sh

# 1) Ensure Desired dump normalizes output file after export (endpoint 0/none -> empty, pad to 5 fields)
python3 - <<'PY'
from pathlib import Path

p = Path("/opt/vpn-service/scripts/stage3/stage3_05_desired_db_dump.sh")
s = p.read_text(encoding="utf-8", errors="ignore")

marker = "### S35_NORMALIZE_OUT ###"
if marker in s:
    print("OK: desired already patched")
else:
    inject = r'''
  ### S35_NORMALIZE_OUT ###
  # Normalize desired TSV:
  # - ensure 5 columns: pubkey,allowed,endpoint,keepalive,enabled
  # - endpoint: treat 0/(none)/NULL as empty
  # - keepalive: empty -> 0
  # - enabled: empty -> 1
  if [[ -f "$OUT" ]]; then
    tmp="${OUT}.tmp"
    awk -F $'\t' 'BEGIN{OFS="\t"}{
      # pad to 5 columns
      for(i=NF+1;i<=5;i++) $i="";
      # normalize endpoint
      if($3=="0" || $3=="(none)") $3="";
      # normalize keepalive/enabled
      if($4=="") $4="0";
      if($5=="") $5="1";
      print
    }' "$OUT" >"$tmp" && mv -f "$tmp" "$OUT"
  fi
'''
    # Try to insert right after "BAD_FORMAT=..." summary or after export block; fall back to end of main() before Summary.
    if "BAD_FORMAT=" in s:
        # insert after first occurrence of BAD_FORMAT printing (safe place, after file created)
        idx = s.find("BAD_FORMAT=")
        # insert after the line containing BAD_FORMAT=...
        line_end = s.find("\n", idx)
        s = s[:line_end+1] + inject + s[line_end+1:]
    else:
        # append near end
        s += "\n" + inject + "\n"
    p.write_text(s, encoding="utf-8")
    print("OK: patched desired:", p)
PY

# 2) Ensure Actual dump always emits 5 columns and endpoint "0/(none)" => empty as well
python3 - <<'PY'
from pathlib import Path

p = Path("/opt/vpn-service/scripts/stage3/stage3_05_actual_wg_dump.sh")
s = p.read_text(encoding="utf-8", errors="ignore")

marker = "### S35_NORMALIZE_OUT ###"
if marker in s:
    print("OK: actual already patched")
else:
    inject = r'''
  ### S35_NORMALIZE_OUT ###
  # Normalize actual TSV to 5 cols and endpoint 0/(none) -> empty (some kernels print (none))
  if [[ -f "$OUT" ]]; then
    tmp="${OUT}.tmp"
    awk -F $'\t' 'BEGIN{OFS="\t"}{
      for(i=NF+1;i<=5;i++) $i="";
      if($3=="0" || $3=="(none)") $3="";
      if($4=="") $4="0";
      if($5=="") $5="1";
      print
    }' "$OUT" >"$tmp" && mv -f "$tmp" "$OUT"
  fi
'''
    # Insert after file creation / wc -l output block; easiest: after first "ACTUAL_FILE=" echo in summary, but we want before summary.
    # We'll just append near the end of the script; it’s safe because OUT is already known.
    s += "\n" + inject + "\n"
    p.write_text(s, encoding="utf-8")
    print("OK: patched actual:", p)
PY

# 3) Patch diff: normalize endpoint equivalence (0/(none)/empty) and ensure maps compare normalized 5-field records.
python3 - <<'PY'
from pathlib import Path
import re

p = Path("/opt/vpn-service/scripts/stage3/stage3_05_diff.sh")
s = p.read_text(encoding="utf-8", errors="ignore")

# Add a small normalization helper if not present
if "s35_norm_ep()" not in s:
    helper = r'''
s35_norm_ep() {
  # endpoint normalization: treat 0/(none)/empty as empty; if no host:port, empty.
  local ep="${1:-}"
  ep="${ep//$'\r'/}"
  ep="${ep//$'\n'/}"
  [[ "$ep" == "0" || "$ep" == "(none)" ]] && ep=""
  # if it's non-empty but doesn't look like host:port, treat as empty (prevents "0" or garbage causing UPD)
  if [[ -n "$ep" && "$ep" != *:* ]]; then
    ep=""
  fi
  printf '%s' "$ep"
}
'''
    s = helper + "\n" + s

# Replace record-building so it normalizes endpoint and pads fields.
# We patch by inserting normalization right before comparisons: easiest is to normalize desired/actual temp files after load.
marker = "### S35_NORMALIZE_INPUTS ###"
if marker not in s:
    inject = r'''
### S35_NORMALIZE_INPUTS ###
norm_tsv_5cols() {
  local in="$1" out="$2"
  awk -F $'\t' 'BEGIN{OFS="\t"}{
    for(i=NF+1;i<=5;i++) $i="";
    if($3=="0" || $3=="(none)") $3="";
    if($4=="") $4="0";
    if($5=="") $5="1";
    print
  }' "$in" >"$out"
}
'''
    s = inject + "\n" + s

# Try to find where DESIRED_FILE/ACTUAL_FILE are used; add normalization right after they are set/validated.
# We'll insert after the line that echoes DESIRED_FILE/ACTUAL_FILE (or after "FAIL missing" checks).
insert_after_patterns = [
    r'echo "DESIRED_FILE=\$DESIRED_FILE"',
    r'echo "ACTUAL_FILE=\$ACTUAL_FILE"',
]
for pat in insert_after_patterns:
    m = re.search(pat, s)
    if m:
        # insert only once, after the first match
        pos = s.find("\n", m.end())
        if "norm_tsv_5cols" not in s[m.end():m.end()+500]:
            s = s[:pos+1] + r'''
  # Normalize inputs to stable 5-col TSV before building maps
  DESIRED_NORM="/tmp/stage35_desired_norm_$$.tsv"
  ACTUAL_NORM="/tmp/stage35_actual_norm_$$.tsv"
  norm_tsv_5cols "$DESIRED_FILE" "$DESIRED_NORM"
  norm_tsv_5cols "$ACTUAL_FILE"  "$ACTUAL_NORM"
  DESIRED_FILE="$DESIRED_NORM"
  ACTUAL_FILE="$ACTUAL_NORM"
''' + s[pos+1:]
        break

p.write_text(s, encoding="utf-8")
print("OK: patched diff:", p)
PY

chmod +x /opt/vpn-service/scripts/stage3/stage3_05_*.sh /opt/vpn-service/scripts/stage3/stage3_05_hotfix_normalize.sh || true
echo "[*] Done. Now rerun Stage 3.5: 1 -> 2 -> 3 (expect RESULT=NO_CHANGES)."
