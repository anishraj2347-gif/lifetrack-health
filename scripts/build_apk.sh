#!/bin/bash
# Release APK for the demo phone. Obfuscated: class and function names are
# scrambled in the shipped code; the symbol map stays here (build/symbols,
# gitignored) to read crash traces. Pass LT_DEMO_TOOLS=false for a non-demo build.
set -euo pipefail
cd "$(dirname "$0")/../app"
flutter build apk --release \
  --obfuscate --split-debug-info=build/symbols \
  --dart-define=LT_RELAY_URL="${LT_RELAY_URL:-http://127.0.0.1:8787}" \
  --dart-define=LT_REGISTRY_KEY="${LT_REGISTRY_KEY:-88IHsgHh2NSLizhkZN8Zh6SuPax8oyRJmogFFJTu5LA=}" \
  --dart-define=LT_IDENTITY="${LT_IDENTITY:-required}" \
  --dart-define=LT_DEMO_TOOLS="${LT_DEMO_TOOLS:-true}"
