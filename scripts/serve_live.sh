#!/bin/bash
# What the laptop's login service runs (scripts/install_laptop_server.sh):
# the compiled LifeTrack server on this laptop's network address. Identity
# checks use the real DigiLocker as soon as server/data/digilocker.json holds
# the partner keys; until then the practice stand-in (sample people only).
set -euo pipefail
# Every file the server writes (IDs, backups, doctor list) is owner-only.
umask 077
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IP=$("$ROOT/scripts/lan_ip.sh")
PORT="${LT_PORT:-8787}"
cd "$ROOT/server"
IDENTITY=(--require-identity)
# Practice mode: the stand-in DigiLocker, and IDs for the demo build's sample people.
[ -f data/digilocker.json ] || IDENTITY+=(--practice-digilocker --allow-sample-ids)
exec "$ROOT/server/build/lifetrack_server" --port "$PORT" --data data --lan \
  --public-base "http://$IP:$PORT" "${IDENTITY[@]}"
