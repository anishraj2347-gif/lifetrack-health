#!/bin/bash
# Runs the LifeTrack server for the phone on the same home Wi-Fi (no cable).
# Identity stays required, through the practice DigiLocker stand-in (sample
# people) until LifeTrack is a DigiLocker partner. Leave this running.
#
# The first time, macOS asks whether "dart" may accept incoming connections:
# choose Allow. If the laptop's address changes, rebuild the APK
# (scripts/build_apk.sh) so the phone knows the new one.
set -euo pipefail
cd "$(dirname "$0")"
IP=$(./lan_ip.sh)
PORT="${LT_PORT:-8787}"
cd ../server
exec dart run bin/server.dart --port "$PORT" --data data --lan \
  --public-base "http://$IP:$PORT" \
  --practice-digilocker --require-identity
