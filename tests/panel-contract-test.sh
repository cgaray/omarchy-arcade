#!/bin/bash

# Check the bar-widget contract that qmllint cannot resolve.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HERE/.."
MANIFEST="$ROOT/manifest.json"

failures=0
passed=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ $expected == "$actual" ]]; then
    passed=$((passed + 1))
  else
    echo "FAIL: $name"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    failures=$((failures + 1))
  fi
}

ENTRY=$(jq -r '.entryPoints.barWidget // ""' "$MANIFEST")
check "the manifest names a barWidget entry point" "Panel.qml" "$ENTRY"

check "the entry point exists" "yes" "$([[ -f $ROOT/$ENTRY ]] && echo yes || echo no)"

check "the manifest declares the bar-widget kind" \
  "true" "$(jq '(.kinds | index("bar-widget")) != null' "$MANIFEST")"

# Check the overlay kind and entry point.
OVERLAY=$(jq -r '.entryPoints.overlay // ""' "$MANIFEST")
check "the manifest declares the overlay kind" \
  "true" "$(jq '(.kinds | index("overlay")) != null' "$MANIFEST")"

check "the manifest names an overlay entry point" "Overlay.qml" "$OVERLAY"

check "the overlay entry point exists" "yes" "$([[ -f $ROOT/$OVERLAY ]] && echo yes || echo no)"

# Check the overlay lifecycle functions.
for fn in "function open" "function close" "function toggle"; do
  check "the overlay defines $fn" \
    "true" "$(grep -qE "^\s*$fn\(" "$ROOT/$OVERLAY" && echo true || echo false)"
done

check "the overlay dismisses itself through the shell host" \
  "true" "$(grep -q 'shell.hide(root.pluginId)' "$ROOT/$OVERLAY" && echo true || echo false)"

# Both surfaces reach the same helpers: the launcher from each surface
# directly, the scanner through the shared ArcadeLibrary component.
for script in omarchy-arcade-scan omarchy-arcade-launch; do
  check "$script is referenced by the overlay" \
    "true" "$(grep -qF "$script" "$ROOT/$OVERLAY" "$ROOT/ArcadeLibrary.qml" && echo true || echo false)"
done

# Check the widget display name.
check "the widget has a display name" \
  "true" "$(jq '((.barWidget.displayName // "") | length) > 0' "$MANIFEST")"

check "every settings key has a default" \
  "true" "$(jq '[.barWidget.schema[].key] - [.barWidget.defaults | keys[]] | length == 0' "$MANIFEST")"

PANEL="$ROOT/$ENTRY"

check "the root type is Ui.Panel" \
  "1" "$(grep -cE '^Panel \{' "$PANEL")"

# Check the root size contract.
check "the root forwards implicitWidth from the bar button" \
  "1" "$(grep -cE '^\s*implicitWidth: button\.implicitWidth' "$PANEL")"

check "the root forwards implicitHeight from the bar button" \
  "1" "$(grep -cE '^\s*implicitHeight: button\.implicitHeight' "$PANEL")"

check "there is a bar button with that id" \
  "1" "$(grep -cE '^\s*id: button' "$PANEL")"

# manageIpc:false hands the IpcHandler to us; forgetting to write one leaves
# `omarchy-shell io.github.cgaray.arcade toggle` answering "Target not found".
if grep -qE '^\s*manageIpc: false' "$PANEL"; then
  check "manageIpc:false is paired with an IpcHandler" \
    "1" "$(grep -cE '^\s*IpcHandler \{' "$PANEL")"
  check "the IpcHandler target matches the plugin id" \
    "1" "$(grep -cE "^\s*target: \"$(jq -r .id "$MANIFEST")\"" "$PANEL")"
fi

# Check helper paths and permissions. The scanner is spawned by the shared
# ArcadeLibrary component, which both surfaces instantiate; the launcher is
# referenced from each surface directly.
for script in omarchy-arcade-scan omarchy-arcade-launch; do
  check "$script is referenced by the panel" \
    "true" "$(grep -qF "$script" "$PANEL" "$ROOT/ArcadeLibrary.qml" && echo true || echo false)"
  check "$script is executable" \
    "true" "$([[ -x $ROOT/bin/$script ]] && echo true || echo false)"
done

# Detached commands must use absolute executable paths.
for qml in "$PANEL" "$ROOT/$OVERLAY"; do
  bare=$(grep -A1 'execDetached(\[$' "$qml" | grep -cE '^\s*"[a-z][a-z0-9-]*"' || true)
  check "$(basename "$qml") spawns nothing by bare command name" "0" "$bare"
done

if (( failures )); then
  echo "panel-contract-test: $passed passed, $failures failed"
  exit 1
fi
echo "panel-contract-test: $passed passed"
