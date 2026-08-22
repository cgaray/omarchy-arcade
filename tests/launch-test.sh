#!/bin/bash

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCH="$HERE/../bin/omarchy-arcade-launch"
FIXTURE=$(mktemp -d -t arcade-launch-XXXXXX) || exit 1
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/bin" "$FIXTURE/state" "$FIXTURE/home"
touch "$FIXTURE/core.so" "$FIXTURE/game.rom"

cat >"$FIXTURE/bin/omarchy-shell" <<'SCRIPT'
#!/bin/bash
printf 'shell %s\n' "$*" >>"$FAKE_LOG"
SCRIPT

cat >"$FIXTURE/bin/omarchy-toggle-idle" <<'SCRIPT'
#!/bin/bash
printf 'idle %s\n' "$*" >>"$FAKE_LOG"
SCRIPT

cat >"$FIXTURE/bin/retroarch" <<'SCRIPT'
#!/bin/bash
printf 'retroarch %s\n' "$*" >>"$FAKE_LOG"
exit "${FAKE_RETROARCH_STATUS:-0}"
SCRIPT
chmod +x "$FIXTURE/bin"/*

run_launch() {
  PATH="$FIXTURE/bin:$PATH" \
  HOME="$FIXTURE/home" \
  XDG_STATE_HOME="$FIXTURE/state" \
  FAKE_LOG="$FIXTURE/calls.log" \
  FAKE_RETROARCH_STATUS="${FAKE_RETROARCH_STATUS:-0}" \
  "$LAUNCH" --core "$FIXTURE/core.so" --rom "$FIXTURE/game.rom" "$@"
}

failures=0
check() {
  local name="$1" expected="$2" actual="$3"
  if [[ $expected == "$actual" ]]; then return 0; fi
  echo "FAIL: $name"
  echo "  expected: $expected"
  echo "  actual:   $actual"
  failures=$((failures + 1))
}

run_launch
check "successful play is recorded" "1" "$(jq '. | length' "$FIXTURE/state/omarchy-arcade/plays.json")"
check "RetroArch launches fullscreen" "1" "$(grep -c 'retroarch .*--fullscreen' "$FIXTURE/calls.log")"
check "desktop state tools are never called" "0" "$(grep -cE '^(shell|idle) ' "$FIXTURE/calls.log" || true)"

: >"$FIXTURE/calls.log"
FAKE_RETROARCH_STATUS=7 run_launch
status=$?
check "emulator status is preserved" "7" "$status"

: >"$FIXTURE/calls.log"
run_launch --slot 3
check "numeric slots use entryslot" "1" "$(grep -c -- '--entryslot 3' "$FIXTURE/calls.log")"

: >"$FIXTURE/calls.log"
run_launch --slot auto
check "auto slots use an appended config" "1" "$(grep -c -- '--appendconfig .*arcade-resume-' "$FIXTURE/calls.log")"

: >"$FIXTURE/calls.log"
run_launch --slot 12 >/dev/null 2>&1
check "invalid slots are rejected" "1" "$?"

if (( failures )); then
  echo "launch-test: $failures failed"
  exit 1
fi
echo "launch-test: 7 passed"
