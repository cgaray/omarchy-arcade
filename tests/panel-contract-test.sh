#!/bin/bash

# Checks the bar-widget contract that has no compile-time enforcement.
#
# qmllint cannot help here: a file whose root type comes from qs.Ui (Panel)
# is unresolvable without Quickshell's type information, so qmllint exits
# non-zero on every bar widget including the first-party ones. What it would
# not have caught anyway is the contract below -- the shell loads a widget
# missing any of it without a single warning, and it renders as a gap in the
# bar. Each check here is a bug that actually happened.

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

# The plugin ships two surfaces from one id. The shell instantiates them as
# separate object trees through separate code paths, and a kind declared
# without its entry point loads as nothing at all with only a console line to
# explain it -- so check the pairing here.
OVERLAY=$(jq -r '.entryPoints.overlay // ""' "$MANIFEST")
check "the manifest declares the overlay kind" \
  "true" "$(jq '(.kinds | index("overlay")) != null' "$MANIFEST")"

check "the manifest names an overlay entry point" "Overlay.qml" "$OVERLAY"

check "the overlay entry point exists" "yes" "$([[ -f $ROOT/$OVERLAY ]] && echo yes || echo no)"

# The shell calls these by name on the loaded object; a rename is silent.
for fn in "function open" "function close" "function toggle"; do
  check "the overlay defines $fn" \
    "true" "$(grep -qE "^\s*$fn\(" "$ROOT/$OVERLAY" && echo true || echo false)"
done

check "the overlay dismisses itself through the shell host" \
  "true" "$(grep -q 'shell.hide(root.pluginId)' "$ROOT/$OVERLAY" && echo true || echo false)"

# Both surfaces spawn the same helpers by path.
for script in omarchy-arcade-scan omarchy-arcade-launch; do
  check "$script is referenced by the overlay" \
    "true" "$(grep -qF "$script" "$ROOT/$OVERLAY" && echo true || echo false)"
done

# A bar-widget id that is not also in barWidget.displayName territory shows up
# in the bar settings list with no name at all.
check "the widget has a display name" \
  "true" "$(jq '((.barWidget.displayName // "") | length) > 0' "$MANIFEST")"

check "every settings key has a default" \
  "true" "$(jq '[.barWidget.schema[].key] - [.barWidget.defaults | keys[]] | length == 0' "$MANIFEST")"

PANEL="$ROOT/$ENTRY"

check "the root type is Ui.Panel" \
  "1" "$(grep -cE '^Panel \{' "$PANEL")"

# The bar sizes each slot from its widget's implicit size. A root that reports
# nothing collapses the slot to zero width, and the widget silently renders as
# a gap -- no warning, no error, nothing in the log.
check "the root forwards implicitWidth from the bar button" \
  "1" "$(grep -cE '^\s*implicitWidth: button\.implicitWidth' "$PANEL")"

check "the root forwards implicitHeight from the bar button" \
  "1" "$(grep -cE '^\s*implicitHeight: button\.implicitHeight' "$PANEL")"

check "there is a bar button with that id" \
  "1" "$(grep -cE '^\s*id: button' "$PANEL")"

# manageIpc:false hands the IpcHandler to us; forgetting to write one leaves
# `omarchy-shell io.garay.arcade toggle` answering "Target not found".
if grep -qE '^\s*manageIpc: false' "$PANEL"; then
  check "manageIpc:false is paired with an IpcHandler" \
    "1" "$(grep -cE '^\s*IpcHandler \{' "$PANEL")"
  check "the IpcHandler target matches the plugin id" \
    "1" "$(grep -cE "^\s*target: \"$(jq -r .id "$MANIFEST")\"" "$PANEL")"
fi

# Both helper scripts are spawned by path from the panel, so a rename that
# misses one is a button that does nothing.
for script in omarchy-arcade-scan omarchy-arcade-launch; do
  check "$script is referenced by the panel" \
    "true" "$(grep -qF "$script" "$PANEL" && echo true || echo false)"
  check "$script is executable" \
    "true" "$([[ -x $ROOT/bin/$script ]] && echo true || echo false)"
done

# execDetached does not go through a shell and does not inherit a login PATH,
# so a bare command name spawns nothing at all -- no error, no log line. Every
# spawn must therefore be an absolute path built from OMARCHY_PATH or the
# plugin directory. This is the bug that made "b" and the install button no-ops.
# Only the first element is the binary; later elements are arguments, and one
# of them is legitimately a bare command name handed to a terminal launcher
# that does go through a shell.
for qml in "$PANEL" "$ROOT/$OVERLAY"; do
  bare=$(grep -A1 'execDetached(\[$' "$qml" | grep -cE '^\s*"[a-z][a-z0-9-]*"' || true)
  check "$(basename "$qml") spawns nothing by bare command name" "0" "$bare"
done

if (( failures )); then
  echo "panel-contract-test: $passed passed, $failures failed"
  exit 1
fi
echo "panel-contract-test: $passed passed"
