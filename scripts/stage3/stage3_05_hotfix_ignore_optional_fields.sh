#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

echo "[*] Hotfix: treat desired endpoint/keepalive as optional when empty/0"

python3 - <<'PY'
from pathlib import Path
import re

# ---------- PATCH DIFF ----------
p = Path("/opt/vpn-service/scripts/stage3/stage3_05_diff.sh")
s = p.read_text(encoding="utf-8", errors="ignore")

# We want comparison rules:
# - always compare allowed_ips and enabled
# - compare endpoint only if desired endpoint not empty
# - compare keepalive only if desired keepalive > 0
#
# Implementation approach (robust): introduce a normalizer function and a "cmp" function used for drift detection.
# We'll inject helper near top, then patch drift decision if we can locate it; otherwise we append a safe override that
# re-writes the "comparable signature" used in maps if signatures exist.

if "s35_cmp_record()" not in s:
    helper = r'''
# --- S35 HOTFIX: optional fields in desired ---
s35_norm_ep() {
  local ep="${1:-}"
  ep="${ep//$'\r'/}"; ep="${ep//$'\n'/}"
  [[ "$ep" == "0" || "$ep" == "(none)" ]] && ep=""
  printf '%s' "$ep"
}
s35_norm_ka() {
  local ka="${1:-}"
  ka="${ka//$'\r'/}"; ka="${ka//$'\n'/}"
  [[ -z "$ka" ]] && ka="0"
  # keep digits only
  if [[ "$ka" =~ ^[0-9]+$ ]]; then printf '%s' "$ka"; else printf '0'; fi
}
s35_norm_en() {
  local en="${1:-}"
  en="${en//$'\r'/}"; en="${en//$'\n'/}"
  [[ -z "$en" ]] && en="1"
  if [[ "$en" =~ ^[01]$ ]]; then printf '%s' "$en"; else printf '1'; fi
}
s35_cmp_record() {
  # Args: allowed endpoint keepalive enabled
  # desired-side: endpoint/keepalive may be optional; caller decides by passing desired values.
  local allowed="$1" ep="$2" ka="$3" en="$4"
  ep="$(s35_norm_ep "$ep")"
  ka="$(s35_norm_ka "$ka")"
  en="$(s35_norm_en "$en")"
  printf '%s|%s|%s|%s' "$allowed" "$ep" "$ka" "$en"
}
'''
    s = helper + "\n" + s

# Now patch the UPD detection logic.
# Common pattern in such scripts: compare desired_record != actual_record or compare fields directly.
# We'll try a few regex replacements.

# 1) If script builds strings like: desired_sig="$allowed|$endpoint|$keepalive|$enabled"
# replace with: desired_sig="$(s35_cmp_record "$allowed" "$endpoint" "$keepalive" "$enabled")"
s2 = re.sub(
    r'desired_sig="\$\{?allowed[^"\n]*\}\?\|\$\{?endpoint[^"\n]*\}\?\|\$\{?keepalive[^"\n]*\}\?\|\$\{?enabled[^"\n]*\}\?"',
    'desired_sig="$(s35_cmp_record "$allowed" "$endpoint" "$keepalive" "$enabled")"',
    s
)
s = s2

# 2) Patch actual_sig similarly
s2 = re.sub(
    r'actual_sig="\$\{?allowed[^"\n]*\}\?\|\$\{?endpoint[^"\n]*\}\?\|\$\{?keepalive[^"\n]*\}\?\|\$\{?enabled[^"\n]*\}\?"',
    'actual_sig="$(s35_cmp_record "$allowed_a" "$endpoint_a" "$keepalive_a" "$enabled_a")"',
    s
)
s = s2

# 3) If script compares endpoint/keepalive directly in UPD:
# Replace drift condition to ignore endpoint if desired empty and ignore keepalive if desired 0.
# We'll try to locate a line containing "UPD" and "endpoint" or "keepalive".
if "desired_ep" in s and "actual_ep" in s:
    # no-op; too risky to guess variable names
    pass

# Fallback: if we can locate a comparison like: if [[ "$drec" != "$arec" ]]; then UPD
# we patch to compute arec_adjusted: replace actual endpoint/keepalive with desired ones when desired is optional.
pattern = r'if\s+\[\[\s*"\$drec"\s*!=\s*"\$arec"\s*\]\]\s*;\s*then'
if re.search(pattern, s):
    repl = r'''
# S35 HOTFIX: make desired optional fields not trigger UPD
# if desired endpoint empty -> ignore endpoint drift
# if desired keepalive == 0 -> ignore keepalive drift
arec_adj="$arec"
if [[ -z "$(s35_norm_ep "$dep")" ]]; then
  # dep empty => force endpoint in actual signature to empty for comparison
  # (assumes arec encoded as allowed|endpoint|keepalive|enabled)
  IFS='|' read -r _a_allowed _a_ep _a_ka _a_en <<<"$arec_adj"
  arec_adj="${_a_allowed}|$(s35_norm_ep "")|${_a_ka}|${_a_en}"
fi
if [[ "$(s35_norm_ka "$dka")" == "0" ]]; then
  IFS='|' read -r _a_allowed _a_ep _a_ka _a_en <<<"$arec_adj"
  arec_adj="${_a_allowed}|${_a_ep}|0|${_a_en}"
  IFS='|' read -r _d_allowed _d_ep _d_ka _d_en <<<"$drec"
  drec="${_d_allowed}|${_d_ep}|0|${_d_en}"
fi
if [[ "$drec" != "$arec_adj" ]]; then
'''
    s = re.sub(pattern, repl, s, count=1)

p.write_text(s, encoding="utf-8")
print("OK patched:", p)

# ---------- PATCH APPLY ----------
p = Path("/opt/vpn-service/scripts/stage3/stage3_05_reconcile_apply.sh")
s = p.read_text(encoding="utf-8", errors="ignore")

# We will make UPD apply only what is explicitly set in plan:
# - endpoint: apply only if non-empty and contains ':'
# - keepalive: apply only if >0
# We'll patch around where wg set is called. We'll do a safe insertion: define helpers + replace simple wg set lines.

if "s35_apply_peer()" not in s:
    helper = r'''
# --- S35 HOTFIX: apply optional fields safely ---
s35_apply_peer() {
  # args: iface pub allowed endpoint keepalive enabled action
  local iface="$1" pub="$2" allowed="$3" ep="$4" ka="$5" en="$6" action="$7"
  ep="${ep//$'\r'/}"; ep="${ep//$'\n'/}"
  ka="${ka//$'\r'/}"; ka="${ka//$'\n'/}"
  [[ -z "$ka" ]] && ka="0"

  # Build wg set args
  local args=()
  args+=(peer "$pub")
  # allowed ips always meaningful for ADD/UPD
  [[ -n "$allowed" ]] && args+=(allowed-ips "$allowed")

  # endpoint is optional; must be host:port
  if [[ -n "$ep" && "$ep" != "0" && "$ep" == *:* ]]; then
    args+=(endpoint "$ep")
  fi

  # keepalive optional; apply only if >0
  if [[ "$ka" =~ ^[0-9]+$ ]] && [[ "$ka" -gt 0 ]]; then
    args+=(persistent-keepalive "$ka")
  fi

  # enabled flag: if 0 -> remove peer (treat as DEL)
  if [[ "$en" == "0" ]]; then
    echo "[DEL(enabled=0)] $pub"
    wg set "$iface" peer "$pub" remove
    return 0
  fi

  echo "wg set $iface ${args[*]}"
  wg set "$iface" "${args[@]}"
}
'''
    s = helper + "\n" + s

# Replace any direct "wg set $IFACE peer ..." execution with call to s35_apply_peer if we can locate it.
# We'll patch a common simple pattern: wg set "$IFACE" peer "$pub" allowed-ips "$allowed" endpoint "$ep" persistent-keepalive "$ka"
s = re.sub(
    r'wg\s+set\s+"\$IFACE"\s+peer\s+"\$pub"[^;\n]*',
    r's35_apply_peer "$IFACE" "$pub" "${allowed:-}" "${endpoint:-}" "${keepalive:-0}" "${enabled:-1}" "${op:-UPD}"',
    s
)

p.write_text(s, encoding="utf-8")
print("OK patched:", p)
PY

chmod +x /opt/vpn-service/scripts/stage3/stage3_05_diff.sh /opt/vpn-service/scripts/stage3/stage3_05_reconcile_apply.sh
echo "[*] Done. Now rerun Stage 3.5: 1 -> 2 -> 3. Expect RESULT=NO_CHANGES."
