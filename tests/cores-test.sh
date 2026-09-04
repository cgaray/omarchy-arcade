#!/bin/bash

# Covers the two lock-taking paths in omarchy-arcade-cores. Both open a
# predictable lock path with shell redirection, which follows symlinks -- so
# the open must not be one that truncates.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORES="$HERE/../bin/omarchy-arcade-cores"
FIXTURE=$(mktemp -d -t arcade-cores-XXXXXX) || exit 1
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/ra" "$FIXTURE/cores" "$FIXTURE/cfg/omarchy/arcade"
touch "$FIXTURE/cores/fceumm_libretro.so"
printf 'libretro_directory = "%s"\n' "$FIXTURE/cores" >"$FIXTURE/ra/retroarch.cfg"

CONF="$FIXTURE/cfg/omarchy/arcade/cores.conf"
LOCK="$CONF.lock"

run_cores() {
  HOME="$FIXTURE" \
  XDG_CONFIG_HOME="$FIXTURE/cfg" \
  RA_CONFIG_DIR="$FIXTURE/ra" \
  "$CORES" "$@"
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

check "set records a choice" "ok" "$(run_cores set nes fceumm 2>&1)"
check "the choice is written" "nes = fceumm" "$(grep '^nes' "$CONF")"
# Captured first: under `pipefail` a pipeline would report the script's own
# non-zero exit rather than grep's verdict.
refusal=$(run_cores set nes nosuchcore 2>&1)
check "set refuses an uninstalled core" "true" \
  "$(grep -qF 'not installed' <<<"$refusal" && echo true || echo false)"
check "unset forgets a choice" "ok" "$(run_cores unset nes 2>&1)"
check "the choice is gone" "0" "$(grep -c '^nes' "$CONF" || true)"

# A symlink at the lock path must survive both lock-taking paths intact.
printf 'do not truncate me\n' >"$FIXTURE/lock-target"

rm -f "$LOCK"
ln -s "$FIXTURE/lock-target" "$LOCK"
run_cores set nes fceumm >/dev/null 2>&1
check "set does not truncate a lock symlink target" "do not truncate me" \
  "$(cat "$FIXTURE/lock-target")"

rm -f "$LOCK"
ln -s "$FIXTURE/lock-target" "$LOCK"
run_cores unset nes >/dev/null 2>&1
check "unset does not truncate a lock symlink target" "do not truncate me" \
  "$(cat "$FIXTURE/lock-target")"

if (( failures )); then
  echo "cores-test: $failures failed"
  exit 1
fi
echo "cores-test: 7 passed"
