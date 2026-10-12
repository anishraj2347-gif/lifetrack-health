#!/bin/bash
# Release APK for the phone. Obfuscated: class and function names are
# scrambled in the shipped code; the symbol map stays here (build/symbols,
# gitignored) to read crash traces.
#
# LT_SERVER=lan (default): the phone talks to scripts/run_server_lan.sh on
#   this laptop over the home Wi-Fi. The laptop's current address is built in
#   (and allowed as the one plain-HTTP host in the network security config,
#   for this build only; the file is restored afterwards).
# LT_SERVER=usb: the phone reaches 127.0.0.1 through `adb reverse tcp:8787 tcp:8787`.
# LT_DEMO_TOOLS=true: a demonstration copy (sample records, sample page,
#   opens on a phone with no screen lock). Off by default.
set -euo pipefail
cd "$(dirname "$0")"
SERVER="${LT_SERVER:-lan}"
PORT="${LT_PORT:-8787}"
CONFIG=../app/android/app/src/main/res/xml/network_security_config.xml
if [ "$SERVER" = lan ]; then
  IP=$(./lan_ip.sh)
  RELAY="${LT_RELAY_URL:-http://$IP:$PORT}"
  # The copy goes outside res/: Android refuses any file there not ending in .xml.
  SAVED=$(mktemp)
  cp "$CONFIG" "$SAVED"
  trap 'mv "$SAVED" "$CONFIG"' EXIT
  python3 - "$CONFIG" "$IP" <<'PY'
import sys
path, ip = sys.argv[1], sys.argv[2]
s = open(path).read()
line = '        <domain includeSubdomains="false">localhost</domain>\n'
assert line in s
s = s.replace(line, line + f'        <domain includeSubdomains="false">{ip}</domain>\n', 1)
open(path, 'w').write(s)
PY
  echo "Server address built in: $RELAY"
else
  RELAY="${LT_RELAY_URL:-http://127.0.0.1:$PORT}"
fi
cd ../app
flutter build apk --release \
  --obfuscate --split-debug-info=build/symbols \
  --dart-define=LT_RELAY_URL="$RELAY" \
  --dart-define=LT_REGISTRY_KEY="${LT_REGISTRY_KEY:-88IHsgHh2NSLizhkZN8Zh6SuPax8oyRJmogFFJTu5LA=}" \
  --dart-define=LT_IDENTITY="${LT_IDENTITY:-required}" \
  --dart-define=LT_DEMO_TOOLS="${LT_DEMO_TOOLS:-false}"
