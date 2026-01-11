
#!/usr/bin/env bash
set -Eeuo pipefail

# ------------------------------------------------------------
# Stage 3.5 — RECONCILE APPLY (controlled, local wg set)
# Applies stage35_plan_*.tsv to a WireGuard interface locally.
#
# PLAN format (TSV preferred):
#   ACTION<TAB>PUBKEY<TAB>ALLOWED<TAB>ENDPOINT<TAB>KEEPALIVE<TAB>ENABLED
# Where:
#   ACTION  = ADD | UPD | DEL
#   PUBKEY  = WireGuard peer public key (base64, usually ends with '=')
#   ALLOWED = e.g. 10.8.0.100/32 (empty allowed is permitted, but usually undesirable)
#   ENDPOINT= host:port or [ipv6]:port (optional)
#   KEEPALIVE = integer seconds (0 means do not set)
#   ENABLED = 1/0 (if 0 => treated as DEL)
# ------------------------------------------------------------

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
LAST_ENV="${LAST_ENV:-$OUT_DIR/stage35_last_run.env}"
IFACE="${IFACE:-wg1}"
PLAN_FILE="${PLAN_FILE:-}"

# If PLAN_FILE not explicitly provided, try to resolve from last_run.env,
# otherwise fallback to newest stage35_plan_*.tsv.
resolve_plan_file() {
  if [[ -n "${PLAN_FILE:-}" && -f "$PLAN_FILE" ]]; then
    return 0
  fi

  # Try last_run.env (safe parse)
  if [[ -f "$LAST_ENV" ]]; then
    local v
    v="$(awk -F= '$1=="PLAN_FILE"{sub(/^[^=]+=/,""); print; exit}' "$LAST_ENV" 2>/dev/null || true)"
    if [[ -n "$v" && -f "$v" ]]; then
      PLAN_FILE="$v"
      return 0
    fi
  fi

  # Fallback to latest plan file
  local latest
  latest="$(ls -1t "$OUT_DIR"/stage35_plan_*.tsv 2>/dev/null | head -n1 || true)"
  if [[ -n "$latest" && -f "$latest" ]]; then
    PLAN_FILE="$latest"
    return 0
  fi

  return 1
}

ts_utc() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
stamp()  { date -u +"%Y-%m-%d_%H-%M-%S"; }

log() { echo "$*"; }
die() { echo "FAIL: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"
}

trim() {
  # trims leading/trailing whitespace
  local s="${1:-}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

is_pubkey_valid() {
  local pub="$1"
  [[ "$pub" =~ ^[A-Za-z0-9+/]{43}=$ ]]
}

# Accept host:port, ip:port, [ipv6]:port
is_endpoint_valid() {
  local ep="$1"
  [[ -n "$ep" ]] || return 1
  # [ipv6]:port
  if [[ "$ep" =~ ^\[[0-9a-fA-F:]+\]:[0-9]+$ ]]; then
    return 0
  fi
  # host:port or ipv4:port (basic)
  if [[ "$ep" =~ :[0-9]+$ ]] && [[ "$ep" != "0" ]]; then
    return 0
  fi
  return 1
}

normalize_allowed() {
  local a
  a="$(trim "${1:-}")"
  case "$a" in
    ""|"0"|"(none)"|"NULL"|"null") echo "" ;;
    *) echo "$a" ;;
  esac
}

normalize_endpoint() {
  local e
  e="$(trim "${1:-}")"
  case "$e" in
    ""|"0"|"(none)"|"NULL"|"null") echo "" ;;
    *) echo "$e" ;;
  esac
}

normalize_keepalive() {
  local k
  k="$(trim "${1:-0}")"
  case "$k" in
    ""|"0"|"(none)"|"NULL"|"null") echo "0" ;;
    *) if [[ "$k" =~ ^[0-9]+$ ]]; then echo "$k"; else echo "0"; fi ;;
  esac
}

normalize_enabled() {
  local e
  e="$(trim "${1:-1}")"
  if [[ "$e" =~ ^[0-9]+$ ]]; then
    if (( e > 0 )); then echo "1"; else echo "0"; fi
  else
    echo "1"
  fi
}

# Apply a single peer mutation using wg set
apply_peer() {
  local iface="$1" pub="$2" allowed="$3" endpoint="$4" keepalive="$5" enabled="$6" action="$7"

  if [[ "$enabled" == "0" ]]; then
    action="DEL"
  fi

  case "$action" in
    DEL)
      log "[DEL] $pub"
      wg set "$iface" peer "$pub" remove
      ;;
    ADD|UPD)
      log "[$action] $pub"
      # Build wg command safely
      local cmd=(wg set "$iface" peer "$pub")

      if [[ -n "$allowed" ]]; then
        cmd+=(allowed-ips "$allowed")
      fi

      if is_endpoint_valid "$endpoint"; then
        cmd+=(endpoint "$endpoint")
      fi

      if [[ "$keepalive" =~ ^[0-9]+$ ]] && (( keepalive > 0 )); then
        cmd+=(persistent-keepalive "$keepalive")
      fi

      "${cmd[@]}"
      ;;
    *)
      log "WARN: unknown action [$action] for pub [$pub] — skipping"
      ;;
  esac
}

# Atomic update of last_run.env (KEY=VALUE only)
update_last_env() {
  local report_path="$1"
  mkdir -p "$OUT_DIR"

  # Preserve existing known keys (safe parse)
  local prev_desired prev_actual prev_diff prev_iface
  prev_desired="$(awk -F= '$1=="DESIRED_FILE"{sub(/^[^=]+=/,""); print; exit}' "$LAST_ENV" 2>/dev/null || true)"
  prev_actual="$(awk -F= '$1=="ACTUAL_FILE"{sub(/^[^=]+=/,""); print; exit}' "$LAST_ENV" 2>/dev/null || true)"
  prev_diff="$(awk -F= '$1=="DIFF_FILE"{sub(/^[^=]+=/,""); print; exit}' "$LAST_ENV" 2>/dev/null || true)"
  prev_iface="$(awk -F= '$1=="IFACE"{sub(/^[^=]+=/,""); print; exit}' "$LAST_ENV" 2>/dev/null || true)"

  local tmp
  tmp="$(mktemp "$OUT_DIR/.stage35_last_run.env.XXXXXX")"

  {
    printf "UPDATED_UTC=%s\n" "$(ts_utc)"
    # Prefer current IFACE, else preserve previous
    if [[ -n "${IFACE:-}" ]]; then
      printf "IFACE=%s\n" "$IFACE"
    else
      printf "IFACE=%s\n" "$prev_iface"
    fi

    # Preserve desired/actual/diff if they exist
    printf "DESIRED_FILE=%s\n" "${prev_desired:-}"
    printf "ACTUAL_FILE=%s\n" "${prev_actual:-}"
    printf "PLAN_FILE=%s\n" "${PLAN_FILE:-}"
    printf "DIFF_FILE=%s\n" "${prev_diff:-}"
    printf "LAST_REPORT=%s\n" "${report_path:-}"
  } > "$tmp"

  chmod 664 "$tmp" || true
  mv -f "$tmp" "$LAST_ENV"
}

main() {
  need_cmd wg
  need_cmd awk
  need_cmd sed
  need_cmd head
  need_cmd wc

  resolve_plan_file || die "missing PLAN_FILE (set PLAN_FILE=... or run diff/plan first)"

  [[ -f "$PLAN_FILE" ]] || die "PLAN_FILE not found: $PLAN_FILE"

  local report="$OUT_DIR/report_stage35_apply_$(stamp).log"
  mkdir -p "$OUT_DIR"

  {
    echo "----------------------------------------------------------------"
    echo ">>> Stage 3.5 — RECONCILE APPLY (controlled, local wg set)"
    echo "----------------------------------------------------------------"
    echo "IFACE=$IFACE"
    echo "LAST_ENV=$LAST_ENV"
    echo "PLAN_FILE=$PLAN_FILE"
    echo

    # Plan summary
    local add del upd
    add="$(awk '$1=="ADD"{c++} END{print c+0}' "$PLAN_FILE" 2>/dev/null || echo 0)"
    del="$(awk '$1=="DEL"{c++} END{print c+0}' "$PLAN_FILE" 2>/dev/null || echo 0)"
    upd="$(awk '$1=="UPD"{c++} END{print c+0}' "$PLAN_FILE" 2>/dev/null || echo 0)"

    echo "----------------------------------------------------------------"
    echo ">>> Plan summary"
    echo "----------------------------------------------------------------"
    echo "ADD=$add DEL=$del UPD=$upd"
    echo "Plan preview (top 50):"
    head -n 50 "$PLAN_FILE" || true
    echo

    # Pre-validate all pubkeys (hard fail)
    echo "----------------------------------------------------------------"
    echo ">>> Pre-validate all pubkeys in plan"
    echo "----------------------------------------------------------------"
    local bad_count
    bad_count="$(
      awk '
        BEGIN{bad=0}
        NF==0{next}
        $0 ~ /^[[:space:]]*#/ {next}
        {
          pub=$2
          gsub(/^[[:space:]]+|[[:space:]]+$/,"",pub)
          if (pub !~ /^[A-Za-z0-9+\/]{43}=$/) { bad++; print pub }
        }
        END{ }
      ' "$PLAN_FILE" | wc -l | tr -d " "
    )"
    if [[ "$bad_count" != "0" ]]; then
      echo "BAD_PUBKEYS:"
      awk '
        NF==0{next}
        $0 ~ /^[[:space:]]*#/ {next}
        {
          pub=$2
          gsub(/^[[:space:]]+|[[:space:]]+$/,"",pub)
          if (pub !~ /^[A-Za-z0-9+\/]{43}=$/) print pub
        }
      ' "$PLAN_FILE" | head -n 200
      die "bad pubkeys in plan: $bad_count"
    fi
    echo "OK pubkey validation"
    echo

    echo "----------------------------------------------------------------"
    echo ">>> SAFETY GATE"
    echo "----------------------------------------------------------------"
    echo "This will APPLY locally via: wg set $IFACE ..."
    echo "Type APPLY to continue."
    read -r gate
    [[ "$gate" == "APPLY" ]] || die "aborted"

    echo "----------------------------------------------------------------"
    echo ">>> Apply plan to wg interface"
    echo "----------------------------------------------------------------"

    # If plan is empty -> nothing to do
    if [[ ! -s "$PLAN_FILE" ]]; then
      echo "NO_CHANGES (empty plan file)"
    else
      # Normalize and apply each line
      # Supports TAB or spaces. Empty/missing cols are tolerated.
      while IFS= read -r raw || [[ -n "$raw" ]]; do
        raw="$(trim "$raw")"
        [[ -z "$raw" ]] && continue
        [[ "$raw" =~ ^# ]] && continue

        # Convert multiple spaces to single TAB for easier parsing if no TAB present
        local line="$raw"
        if [[ "$line" != *$'\t'* ]]; then
          # collapse whitespace to single space then translate first fields
          line="$(echo "$line" | tr -s ' ')"
          # split by space into up to 6 fields, then print as TSV
          line="$(awk '
            {
              action=$1; pub=$2; allowed=$3; endpoint=$4; keepalive=$5; enabled=$6;
              # if fewer fields, missing are empty
              print action "\t" pub "\t" allowed "\t" endpoint "\t" keepalive "\t" enabled
            }' <<<"$line")"
        fi

        local action pub allowed endpoint keepalive enabled
        IFS=$'\t' read -r action pub allowed endpoint keepalive enabled <<< "$line"

        action="$(trim "${action:-}")"
        pub="$(trim "${pub:-}")"
        allowed="$(normalize_allowed "${allowed:-}")"
        endpoint="$(normalize_endpoint "${endpoint:-}")"
        keepalive="$(normalize_keepalive "${keepalive:-0}")"
        enabled="$(normalize_enabled "${enabled:-1}")"

        # Normalize action
        action="$(echo "$action" | tr '[:lower:]' '[:upper:]')"
        [[ -z "$action" ]] && continue

        # Validate pubkey again per-line (belt+suspenders)
        is_pubkey_valid "$pub" || die "invalid pubkey in plan line: [$raw]"

        # Safety: never pass endpoint that is clearly not host:port / [ipv6]:port
        if [[ -n "$endpoint" ]] && ! is_endpoint_valid "$endpoint"; then
          # treat as empty instead of failing (prevents endpoint=0 class errors)
          endpoint=""
        fi

        apply_peer "$IFACE" "$pub" "$allowed" "$endpoint" "$keepalive" "$enabled" "$action"
      done < "$PLAN_FILE"
    fi

    echo
    echo "----------------------------------------------------------------"
    echo ">>> Post-check: wg show $IFACE (first 30 lines)"
    echo "----------------------------------------------------------------"
    wg show "$IFACE" | head -n 30 || true

    echo
    echo "----------------------------------------------------------------"
    echo ">>> DONE"
    echo "----------------------------------------------------------------"
  } 2>&1 | tee "$report"

  update_last_env "$report"
  echo "Report: $report"
}

main "$@"


chmod +x /opt/vpn-service/scripts/stage3/stage3_05_reconcile_apply.sh
bash -n /opt/vpn-service/scripts/stage3/stage3_05_reconcile_apply.sh && echo "OK syntax"
