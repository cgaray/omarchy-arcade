#!/bin/bash
# Sync the working repo into the installed plugin directory.
# Marketplace rule: plugin folders must be real files, no symlinks.
set -euo pipefail
DEST="${HOME}/.config/omarchy/plugins/io.github.cgaray.arcade"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rsync -a --delete \
  --exclude .git --exclude node_modules --exclude '*.bak.*' \
  "$SRC/" "$DEST/"
echo "synced $SRC -> $DEST"
