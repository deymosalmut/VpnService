#!/usr/bin/env bash
set -euo pipefail

IFACE="${1:-wg1}"

wg show "$IFACE" dump | awk '
NR==1 {
  print "{"
  print "  \"interface\": \"" $1 "\","
  print "  \"publicKey\": \"" $3 "\","
  print "  \"listenPort\": " $4 ","
  print "  \"peers\": ["
}
NR>1 {
  # $1 peer_pubkey, $3 allowed_ips, $5 last_handshake_epoch
  printf "    {\"publicKey\":\"%s\",\"allowedIps\":\"%s\",\"lastHandshake\":%s},\n", $1, $3, $5
}
END {
  print "  ]"
  print "}"
}'
