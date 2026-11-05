#!/bin/bash
# Prints this laptop's Wi-Fi (or first wired) IPv4 address (Mac or Windows), for the home-Wi-Fi
# server. Set LT_LAN_IP to override.
set -euo pipefail
if [ -n "${LT_LAN_IP:-}" ]; then echo "$LT_LAN_IP"; exit 0; fi
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*)
    # Windows (Git Bash): the Wi-Fi adapter's address, else the first wired one.
    ip=$(powershell.exe -NoProfile -Command "\$a = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'Wi-Fi' -ErrorAction SilentlyContinue; if (-not \$a) { \$a = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'Ethernet*' -ErrorAction SilentlyContinue | Where-Object { \$_.IPAddress -notlike '169.254.*' } }; (\$a | Select-Object -First 1).IPAddress" 2>/dev/null | tr -d '\r' || true)
    if [ -n "$ip" ]; then echo "$ip"; exit 0; fi
    ;;
  *)
    for i in en0 en1 en2; do
      ip=$(ipconfig getifaddr "$i" 2>/dev/null || true)
      if [ -n "$ip" ]; then echo "$ip"; exit 0; fi
    done
    ;;
esac
echo "No Wi-Fi address found. Join a Wi-Fi network or set LT_LAN_IP." >&2
exit 1
