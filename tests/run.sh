#!/bin/bash

# Everything CI runs, and everything you should run before pushing.
# No display, no shell, no emulator required.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HERE/.."
status=0

step() {
  echo "── $1"
  shift
  if "$@"; then return 0; fi
  status=1
  echo "   ^ failed"
}

# The manifest is the one file the shell reads before trusting anything else,
# so check it the same way the shell will. Skipped off an Omarchy box.
if command -v omarchy-plugin-validate >/dev/null; then
  step "manifest" omarchy-plugin-validate "$ROOT"
else
  step "manifest (jq fallback: omarchy not installed)" \
    jq -e '.schemaVersion == 1 and (.id | length > 0) and (.kinds | index("bar-widget")) != null and (.entryPoints.barWidget | length > 0)' \
    "$ROOT/manifest.json" >/dev/null
fi

for script in "$ROOT"/bin/*; do
  step "bash -n $(basename "$script")" bash -n "$script"
done

# Semantic lint for the plugin scripts; bash -n only proves syntax. Skipped
# where shellcheck is not installed -- GitHub's ubuntu runners ship it.
if command -v shellcheck >/dev/null; then
  for script in "$ROOT"/bin/*; do
    step "shellcheck $(basename "$script")" shellcheck -x "$script"
  done
else
  echo "── shellcheck (skipped: not installed)"
fi

# Overlay.qml has a plain Item root, so qmllint can resolve and check it.
# Panel.qml cannot be linted: its root type comes from qs.Ui, which qmllint
# cannot resolve without Quickshell's type information, and it exits non-zero
# on every bar widget including the first-party ones. panel-contract-test.sh
# covers that file instead.
if command -v qmllint >/dev/null; then
  step "qmllint Library.js" qmllint "$ROOT/Library.js"
  for qml in Overlay.qml ArcadeLibrary.qml PanelFooter.qml ScrollRail.qml SortPicker.qml ShortcutHelp.qml SystemStrip.qml KeyHintBar.qml GameTile.qml InspectorCard.qml ContinueRow.qml LibraryRow.qml; do
    step "qmllint $qml" qmllint -I /usr/share/omarchy/shell "$ROOT/$qml"
  done
else
  echo "── qmllint (skipped: not installed)"
fi

step "bar-widget contract" bash "$HERE/panel-contract-test.sh"
step "qml root references" node "$HERE/qml-refs-test.js" "$ROOT/Panel.qml" "$ROOT/Overlay.qml"
step "architecture seam" node "$HERE/seam-test.js"
step "library unit tests" node "$HERE/library-test.js"
step "session unit tests" node "$HERE/session-test.js"
step "launcher integration tests" bash "$HERE/launch-test.sh"
step "scanner integration tests" bash "$HERE/scan-test.sh"

if (( status )); then
  echo "FAILED"
  exit 1
fi
echo "All checks passed"
