#!/bin/bash
# Analyze and test all five packages. Runs every one even after a failure, so
# one run shows everything that is wrong; exits non-zero if anything failed.
# No server is started and nothing leaves the machine: integration/ joins the
# apps to the real handler in memory.
#
# Usage: scripts/check_all.sh
set -uo pipefail
cd "$(dirname "$0")/.."

failed=()

run() { # package, command...
  local package=$1
  shift
  echo
  echo "== $package: $*"
  if ! (cd "$package" && "$@"); then
    failed+=("$package: $*")
  fi
}

# Pure Dart packages use `dart`; anything depending on Flutter uses `flutter`.
for package in app doctor server packages/lifetrack_protocol integration; do
  if grep -q 'sdk: flutter' "$package/pubspec.yaml"; then
    run "$package" flutter analyze
    run "$package" flutter test
  else
    run "$package" dart pub get
    run "$package" dart analyze
    run "$package" dart test
  fi
done

echo
if [ ${#failed[@]} -eq 0 ]; then
  echo "All five packages: analysis clean, all tests passed."
  exit 0
fi
echo "FAILED:"
printf '  %s\n' "${failed[@]}"
exit 1
