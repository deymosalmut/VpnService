#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
IFACE="${IFACE:-wg1}"

mkdir -p "$OUT_DIR"
ts(){ date -u +"%Y-%m-%d_%H-%M-%S"; }
OUT="$OUT_DIR/stage35_actual_$(ts).tsv"
REPORT="$OUT_DIR/report_stage35_actual_$(ts).log"

log(){ echo -e "$*" | tee -a "$REPORT"; }
hr(){ log "----------------------------------------------------------------"; }
section(){ hr; log ">>> $*"; hr; }

: >"$REPORT"

section "Stage 3.5 — ACTUAL (WG) dump (read-only)"
log "IFACE=$IFACE"
log "OUT=$OUT"

section "Export actual rows (pubkey<TAB>allowed<TAB>endpoint<TAB>keepalive<TAB>enabled=1)"
# wg show IFACE dump:
# peer lines: 1 pubkey 2 psk 3 endpoint 4 allowed_ips 5 handshake 6 rx 7 tx 8 keepalive
wg show "$IFACE" dump \
| tail -n +2 \
| awk -v OFS=$'\t' 'NF>=8{
    pub=$1;
    ep=$3;
    allowed=$4;
    ka=$8;
    if (ep=="(none)") ep="";
    if (allowed=="(none)") allowed="";
    if (ka=="off" || ka=="(none)" || ka=="") ka="0";
    print pub, allowed, ep, ka, 1
  }' >"$OUT"

LINES="$(wc -l <"$OUT" | tr -d ' ')"
log "$LINES $OUT" | tee -a "$REPORT"

section "Preview (top 20)"
head -n 20 "$OUT" | tee -a "$REPORT" || true

section "Summary"
log "ACTUAL_FILE=$OUT"
log "Report: $REPORT"


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

