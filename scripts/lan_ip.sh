#!/bin/bash
# Prints this Mac's Wi-Fi (or first wired) IPv4 address, for the home-Wi-Fi
# server. Set LT_LAN_IP to override.
set -euo pipefail
if [ -n "${LT_LAN_IP:-}" ]; then echo "$LT_LAN_IP"; exit 0; fi
for i in en0 en1 en2; do
  ip=$(ipconfig getifaddr "$i" 2>/dev/null || true)
  if [ -n "$ip" ]; then echo "$ip"; exit 0; fi
done
echo "No Wi-Fi address found. Join a Wi-Fi network or set LT_LAN_IP." >&2
exit 1
