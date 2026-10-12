#!/bin/bash
# Makes this laptop LifeTrack's server (user choice, 12 Oct 2026):
#  - health.lifetrack.server  the server on the Wi-Fi/hotspot address, started
#    at login, restarted if it stops, and keeping the Mac awake (caffeinate -i)
#  - health.lifetrack.clinic  the doctor web app at http://localhost:8080
#    (localhost only: its key store needs a secure page, which plain HTTP on
#    a network address is not)
#  - health.lifetrack.backup  a copy of server/data every night at 03:00
# Logs: ~/Library/Logs/LifeTrack/. Remove with scripts/uninstall_laptop_server.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AGENTS="$HOME/Library/LaunchAgents"
LOGS="$HOME/Library/Logs/LifeTrack"
mkdir -p "$AGENTS" "$LOGS"

echo "Compiling the server…"
(cd "$ROOT/server" && dart pub get >/dev/null && mkdir -p build && dart compile exe bin/server.dart -o build/lifetrack_server >/dev/null)
echo "Building the doctor web app…"
(cd "$ROOT/doctor" && flutter build web --release --dart-define=LT_RELAY_URL=http://127.0.0.1:${LT_PORT:-8787} --dart-define=LT_DEMO_TOOLS=false >/dev/null)

plist() { # label, program args (as <string> lines), extra keys
  cat > "$AGENTS/$1.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$1</string>
  <key>ProgramArguments</key><array>
$2
  </array>
  <key>StandardOutPath</key><string>$LOGS/$1.log</string>
  <key>StandardErrorPath</key><string>$LOGS/$1.log</string>
$3
</dict></plist>
PLIST
}

plist health.lifetrack.server \
"    <string>/usr/bin/caffeinate</string><string>-i</string>
    <string>/bin/bash</string><string>$ROOT/scripts/serve_live.sh</string>" \
"  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>15</integer>"

plist health.lifetrack.clinic \
"    <string>/usr/bin/python3</string><string>-m</string><string>http.server</string>
    <string>8080</string><string>--bind</string><string>127.0.0.1</string>
    <string>--directory</string><string>$ROOT/doctor/build/web</string>" \
"  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>"

plist health.lifetrack.backup \
"    <string>/bin/bash</string><string>$ROOT/scripts/backup_server_data.sh</string>" \
"  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>3</integer><key>Minute</key><integer>0</integer></dict>"

for l in health.lifetrack.server health.lifetrack.clinic health.lifetrack.backup; do
  launchctl bootout "gui/$(id -u)/$l" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$AGENTS/$l.plist"
done
echo "Installed. Server: http://$("$ROOT/scripts/lan_ip.sh" 2>/dev/null || echo '<no network>'):${LT_PORT:-8787}  Doctor app: http://localhost:8080"
