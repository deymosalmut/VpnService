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

#!/usr/bin/env bash
set -Eeuo pipefail


load_kv_env() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[A-Z0-9_]+= ]] || continue
    local k="${line%%=*}"
    local v="${line#*=}"
    v="${v%$'
'}"
    printf -v "$k" '%s' "$v"
  done < "$f"
}

# Populate DESIRED_FILE / ACTUAL_FILE if missing
resolve_inputs() {
  load_kv_env "$LAST_ENV"

  if [[ -z "${DESIRED_FILE:-}" ]]; then
    DESIRED_FILE="$(ls -1t /opt/vpn-service/reports/stage35_desired_*.tsv 2>/dev/null | head -n1 || true)"
  fi
  if [[ -z "${ACTUAL_FILE:-}" ]]; then
    ACTUAL_FILE="$(ls -1t /opt/vpn-service/reports/stage35_actual_*.tsv 2>/dev/null | head -n1 || true)"
  fi
}

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
LAST_ENV="${LAST_ENV:-$OUT_DIR/stage35_last_run.env}"

DESIRED_FILE="${DESIRED_FILE:-}"
ACTUAL_FILE="${ACTUAL_FILE:-}"
resolve_inputs

# Final fallback: choose latest artifacts if still unset
if [[ -z "${DESIRED_FILE:-}" ]]; then
  DESIRED_FILE="$(ls -1t /opt/vpn-service/reports/stage35_desired_*.tsv 2>/dev/null | head -n1 || true)"
fi
if [[ -z "${ACTUAL_FILE:-}" ]]; then
  ACTUAL_FILE="$(ls -1t /opt/vpn-service/reports/stage35_actual_*.tsv 2>/dev/null | head -n1 || true)"
fi
mkdir -p "$OUT_DIR"
ts(){ date -u +"%Y-%m-%d_%H-%M-%S"; }
PLAN="$OUT_DIR/stage35_plan_$(ts).tsv"
DIFF="$OUT_DIR/stage35_diff_$(ts).txt"
REPORT="$OUT_DIR/report_stage35_diff_$(ts).log"

log(){ echo -e "$*" | tee -a "$REPORT"; }
hr(){ log "----------------------------------------------------------------"; }
section(){ hr; log ">>> $*"; hr; }

: >"$REPORT"

section "Stage 3.5 — DIFF/PLAN (read-only)"
log "DESIRED_FILE=${DESIRED_FILE}"
log "ACTUAL_FILE=${ACTUAL_FILE}"
log "PLAN=$PLAN"
log "DIFF=$DIFF"

[[ -n "$DESIRED_FILE" && -f "$DESIRED_FILE" ]] || { log "FAIL missing desired file"; exit 10; }
[[ -n "$ACTUAL_FILE" && -f "$ACTUAL_FILE" ]] || { log "FAIL missing actual file"; exit 11; }

# Normalize into maps: pub -> allowed|endpoint|keepalive|enabled
tmpd="$(mktemp -d)"
trap 'rm -rf "$tmpd"' EXIT

desired_map="$tmpd/desired.map"
actual_map="$tmpd/actual.map"
desired_keys="$tmpd/desired.keys"
actual_keys="$tmpd/actual.keys"

normalize_file_to_map() {
  local in="$1" out="$2"
  awk -F'\t' 'NF>=5{
      pub=$1;
      allowed=$2;
      ep=$3;
      ka=$4;
      en=$5;
      gsub(/\r/,"",pub); gsub(/\r/,"",allowed); gsub(/\r/,"",ep); gsub(/\r/,"",ka); gsub(/\r/,"",en);
      if (pub!="") print pub "\t" allowed "\t" ep "\t" ka "\t" en;
    }' "$in" | sort -u >"$out"
}

section "Normalize desired/actual -> maps"
normalize_file_to_map "$DESIRED_FILE" "$desired_map"
normalize_file_to_map "$ACTUAL_FILE"  "$actual_map"

cut -f1 "$desired_map" | sort -u >"$desired_keys"
cut -f1 "$actual_map"  | sort -u >"$actual_keys"

DESIRED_COUNT="$(wc -l <"$desired_keys" | tr -d ' ')"
ACTUAL_COUNT="$(wc -l <"$actual_keys"  | tr -d ' ')"
log "DESIRED_COUNT=$DESIRED_COUNT"
log "ACTUAL_COUNT=$ACTUAL_COUNT"

# Helpers: get row by pubkey
get_row() {
  local map="$1" pub="$2"
  awk -F'\t' -v p="$pub" '$1==p{print; exit 0}' "$map"
}

: >"$PLAN"
: >"$DIFF"

ADD=0
DEL=0
UPD=0

# ADD/UPD from desired
while read -r pub; do
  drow="$(get_row "$desired_map" "$pub" || true)"
  arow="$(get_row "$actual_map" "$pub" || true)"

  d_allowed="$(printf '%s' "$drow" | cut -f2)"
  d_ep="$(printf '%s' "$drow" | cut -f3)"
  d_ka="$(printf '%s' "$drow" | cut -f4)"
  d_en="$(printf '%s' "$drow" | cut -f5)"

  if [[ -z "$arow" ]]; then
    # If desired says disabled, do nothing (no need to add)
    if [[ "$d_en" == "1" ]]; then
      printf "ADD\t%s\t%s\t%s\t%s\t%s\n" "$pub" "$d_allowed" "$d_ep" "$d_ka" "$d_en" >>"$PLAN"
      echo "[ADD] $pub allowed=$d_allowed ka=$d_ka" >>"$DIFF"
      ADD=$((ADD+1))
    else
      echo "[SKIP disabled desired] $pub" >>"$DIFF"
    fi
    continue
  fi

  a_allowed="$(printf '%s' "$arow" | cut -f2)"
  a_ep="$(printf '%s' "$arow" | cut -f3)"
  a_ka="$(printf '%s' "$arow" | cut -f4)"
  a_en="$(printf '%s' "$arow" | cut -f5)"

  # Drift criteria:
  # - enabled: if desired 0 -> we should DEL
  # - allowed differs (string compare)
  # - keepalive differs
  # endpoint ignored by default (often dynamic on server); if you want strict, add compare.
  if [[ "$d_en" != "1" ]]; then
    printf "DEL\t%s\t\t\t\t0\n" "$pub" >>"$PLAN"
    echo "[DEL disabled desired] $pub" >>"$DIFF"
    DEL=$((DEL+1))
    continue
  fi

  if [[ "$d_allowed" != "$a_allowed" || "$d_ka" != "$a_ka" ]]; then
    printf "UPD\t%s\t%s\t%s\t%s\t%s\n" "$pub" "$d_allowed" "$d_ep" "$d_ka" "$d_en" >>"$PLAN"
    echo "[UPD] $pub allowed:$a_allowed -> $d_allowed ka:$a_ka -> $d_ka" >>"$DIFF"
    UPD=$((UPD+1))
  fi
done <"$desired_keys"

# Orphans in actual => DEL
while read -r pub; do
  if ! grep -qxF "$pub" "$desired_keys"; then
    printf "DEL\t%s\t\t\t\t0\n" "$pub" >>"$PLAN"
    echo "[DEL orphan] $pub" >>"$DIFF"
    DEL=$((DEL+1))
  fi
done <"$actual_keys"

RESULT="NO_CHANGES"
if [[ -s "$PLAN" ]]; then RESULT="CHANGES_PENDING"; fi

section "Summary"
log "RESULT=$RESULT"
log "ADD=$ADD DEL=$DEL UPD=$UPD"
log "PLAN_FILE=$PLAN"
log "DIFF_FILE=$DIFF"

section "DONE"
log "Report: $REPORT"

# Write last_run env (quoted safely)
cat >"$LAST_ENV" <<EENV
UPDATED_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DESIRED_FILE=$DESIRED_FILE
ACTUAL_FILE=$ACTUAL_FILE
PLAN_FILE=$PLAN
DIFF_FILE=$DIFF
LAST_REPORT=$REPORT
EENV
