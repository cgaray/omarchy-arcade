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
if [[ $* == *"notifications dndState"* ]]; then
  printf '%s\n' "${FAKE_DND:-false}"
fi
SCRIPT

cat >"$FIXTURE/bin/omarchy-toggle-idle" <<'SCRIPT'
#!/bin/bash
printf 'idle %s\n' "$*" >>"$FAKE_LOG"
if [[ $1 == status ]]; then
  printf '{"enabled":%s}\n' "${FAKE_IDLE:-false}"
fi
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
  FAKE_DND="${FAKE_DND:-false}" \
  FAKE_IDLE="${FAKE_IDLE:-false}" \
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
check "DND is restored after success" "1" "$(grep -c 'notifications setDnd false' "$FIXTURE/calls.log")"
check "idle is restored after success" "1" "$(grep -c 'idle allow-idle' "$FIXTURE/calls.log")"
check "successful play is recorded" "1" "$(jq '. | length' "$FIXTURE/state/omarchy-arcade/plays.json")"

: >"$FIXTURE/calls.log"
FAKE_DND=true FAKE_IDLE=true FAKE_RETROARCH_STATUS=7 run_launch
status=$?
check "emulator status is preserved" "7" "$status"
check "pre-existing DND is not undone" "0" "$(grep -c 'notifications setDnd false' "$FIXTURE/calls.log")"
check "pre-existing idle is not undone" "0" "$(grep -c 'idle allow-idle' "$FIXTURE/calls.log")"

if (( failures )); then
  echo "launch-test: $failures failed"
  exit 1
fi
echo "launch-test: 6 passed"
