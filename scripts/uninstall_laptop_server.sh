#!/bin/bash
# Stops and removes the LifeTrack login services. server/data and the backups stay.
set -euo pipefail
for l in health.lifetrack.server health.lifetrack.clinic health.lifetrack.backup; do
  launchctl bootout "gui/$(id -u)/$l" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/$l.plist"
done
echo "Removed."
