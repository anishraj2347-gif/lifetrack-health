#!/bin/bash
# Nightly copy of the server's data (LifeTrack IDs, doctor list, encrypted
# backups, the registry signing key). Owner-only; the last 14 are kept.
# The vault backups inside are ciphertext, but the signing key is not:
# keep these copies on this laptop or an encrypted disk.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${LT_BACKUP_DIR:-$HOME/LifeTrack-server-backups}"
mkdir -p "$DEST"; chmod 700 "$DEST"
STAMP=$(date +%Y%m%d-%H%M%S)
tar -czf "$DEST/data-$STAMP.tgz" -C "$ROOT/server" data
chmod 600 "$DEST/data-$STAMP.tgz"
ls -1t "$DEST"/data-*.tgz | tail -n +15 | while read -r old; do rm -f "$old"; done
echo "$(date '+%F %T') backed up to $DEST/data-$STAMP.tgz"
