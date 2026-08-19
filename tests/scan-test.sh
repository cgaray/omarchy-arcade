#!/bin/bash

# Integration test for omarchy-arcade-scan against a fixture library.
#
# Builds a throwaway RetroArch config directory, a fake core, and a ROM folder,
# then asserts on the JSON the scanner emits. Nothing here touches the real
# ~/.config/retroarch, and no emulator is launched.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN="$HERE/../bin/omarchy-arcade-scan"

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

FIXTURE=$(mktemp -d -t arcade-fixture-XXXXXX) || exit 1
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/ra/playlists" "$FIXTURE/ra/states" "$FIXTURE/ra/thumbnails" \
         "$FIXTURE/cores" "$FIXTURE/roms" "$FIXTURE/state" "$FIXTURE/config"

# A core only has to exist; the scanner never loads it.
touch "$FIXTURE/cores/snes9x_libretro.so" "$FIXTURE/cores/gambatte_libretro.so"

cat >"$FIXTURE/ra/retroarch.cfg" <<CFG
libretro_directory = "$FIXTURE/cores"
playlist_directory = "$FIXTURE/ra/playlists"
savestate_directory = "$FIXTURE/ra/states"
thumbnails_directory = "$FIXTURE/ra/thumbnails"
rgui_browser_directory = "$FIXTURE/roms"
CFG

# Names chosen to break naive quoting: a space, an apostrophe, an ampersand.
touch "$FIXTURE/roms/Super Mario World (USA).sfc"
touch "$FIXTURE/roms/Tom's Adventure.sfc"
touch "$FIXTURE/roms/Pinball.gb"
touch "$FIXTURE/roms/notes.txt"          # unmapped extension: must be skipped
touch "$FIXTURE/roms/arcade-set.zip"     # ambiguous extension: must be skipped

run_scan() {
  RA_CONFIG_DIR="$FIXTURE/ra" \
  XDG_STATE_HOME="$FIXTURE/state" \
  XDG_CONFIG_HOME="$FIXTURE/config" \
  "$SCAN"
}

# --- Walk source -------------------------------------------------------------

out=$(run_scan) || { echo "FAIL: scanner exited non-zero"; exit 1; }

jq -e . >/dev/null 2>&1 <<<"$out" || { echo "FAIL: scanner did not emit valid JSON"; exit 1; }
passed=$((passed + 1))

check "walk finds only mapped extensions" \
  "3" "$(jq '.games | length' <<<"$out")"

check "unmapped extensions are skipped" \
  "0" "$(jq '[.games[] | select(.title == "notes")] | length' <<<"$out")"

check "ambiguous .zip is skipped rather than guessed" \
  "0" "$(jq '[.games[] | select(.title == "arcade-set")] | length' <<<"$out")"

check "titles drop the extension" \
  "true" "$(jq '[.games[].title] | contains(["Super Mario World (USA)"])' <<<"$out")"

check "an apostrophe in a filename survives" \
  "true" "$(jq '[.games[].title] | contains(["Tom'"'"'s Adventure"])' <<<"$out")"

check "extension picks the core" \
  "gambatte" "$(jq -r '.games[] | select(.title == "Pinball") | .coreName' <<<"$out")"

check "games are sorted by title" \
  "true" "$(jq '[.games[].title] == ([.games[].title] | sort_by(ascii_downcase))' <<<"$out")"

check "walk games start with no resume" \
  "0" "$(jq '[.games[] | select(.resumeAt > 0)] | length' <<<"$out")"

check "meta reports the walk source" \
  "3" "$(jq '.meta.fromWalk' <<<"$out")"

# --- Save states -------------------------------------------------------------

touch "$FIXTURE/ra/states/Pinball.state"
touch "$FIXTURE/ra/states/Pinball.state.png"
out=$(run_scan)

check "a save state produces a resume slot" \
  "0" "$(jq -r '.games[] | select(.title == "Pinball") | .resumeSlot' <<<"$out")"

check "the state thumbnail is found" \
  "true" "$(jq -r '.games[] | select(.title == "Pinball") | (.resumeArt | endswith("Pinball.state.png"))' <<<"$out")"

check "resumeAt is a real timestamp" \
  "true" "$(jq '.games[] | select(.title == "Pinball") | .resumeAt > 0' <<<"$out")"

# The auto state is newer, so it should win the slot.
sleep 1
touch "$FIXTURE/ra/states/Pinball.state.auto"
out=$(run_scan)
check "the newest state wins, including the auto slot" \
  "auto" "$(jq -r '.games[] | select(.title == "Pinball") | .resumeSlot' <<<"$out")"

# RetroArch's sort_savestates_enable puts states in a per-core subdirectory,
# so the scanner has to find them below the configured directory, not in it.
mkdir -p "$FIXTURE/ra/states/Snes9x"
sleep 1
touch "$FIXTURE/ra/states/Snes9x/Super Mario World (USA).state1"
touch "$FIXTURE/ra/states/Snes9x/Super Mario World (USA).state1.png"
out=$(run_scan)

check "states in a per-core subdirectory are found" \
  "1" "$(jq -r '.games[] | select(.title == "Super Mario World (USA)") | .resumeSlot' <<<"$out")"

check "a subdirectory state's thumbnail is found" \
  "true" "$(jq -r '.games[] | select(.title == "Super Mario World (USA)") | (.resumeArt | endswith(".state1.png"))' <<<"$out")"

check "a state thumbnail is never mistaken for a state" \
  "0" "$(jq '[.games[] | select(.resumeSlot | tostring | endswith("png"))] | length' <<<"$out")"

# --- cores.conf override -----------------------------------------------------

mkdir -p "$FIXTURE/config/omarchy/arcade"
cat >"$FIXTURE/config/omarchy/arcade/cores.conf" <<CONF
# users with an unambiguous library can claim an extension
zip = snes9x
CONF
out=$(run_scan)
check "cores.conf can claim an ambiguous extension" \
  "snes9x" "$(jq -r '.games[] | select(.title == "arcade-set") | .coreName' <<<"$out")"

# --- Playlist source ---------------------------------------------------------

cat >"$FIXTURE/ra/playlists/Nintendo - Super Nintendo Entertainment System.lpl" <<LPL
{
  "version": "1.5",
  "items": [
    {
      "path": "$FIXTURE/roms/Super Mario World (USA).sfc",
      "label": "Super Mario World",
      "core_path": "$FIXTURE/cores/snes9x_libretro.so",
      "core_name": "Snes9x",
      "db_name": "Nintendo - Super Nintendo Entertainment System.lpl"
    },
    {
      "path": "$FIXTURE/roms/deleted-since-scan.sfc",
      "label": "Ghost Entry",
      "core_path": "$FIXTURE/cores/snes9x_libretro.so"
    }
  ]
}
LPL

# Box art lives under the playlist name, which only this source knows.
mkdir -p "$FIXTURE/ra/thumbnails/Nintendo - Super Nintendo Entertainment System/Named_Boxarts"
touch "$FIXTURE/ra/thumbnails/Nintendo - Super Nintendo Entertainment System/Named_Boxarts/Super Mario World.png"

out=$(run_scan)

check "playlists take over from the walk entirely" \
  "0" "$(jq '.meta.fromWalk' <<<"$out")"

check "playlist entries are used" \
  "1" "$(jq '.games | length' <<<"$out")"

check "a playlist entry whose ROM is gone is dropped" \
  "0" "$(jq '[.games[] | select(.title == "Ghost Entry")] | length' <<<"$out")"

check "the playlist label wins over the filename" \
  "Super Mario World" "$(jq -r '.games[0].title' <<<"$out")"

check "box art is resolved from the playlist name" \
  "true" "$(jq -r '.games[0].art | endswith("Named_Boxarts/Super Mario World.png")' <<<"$out")"

check "the system name comes from the playlist" \
  "Nintendo - Super Nintendo Entertainment System" "$(jq -r '.games[0].system' <<<"$out")"

# --- Which core runs the ROM -------------------------------------------------

# The common case: RetroArch scanned a directory and pinned nothing, so every
# entry says DETECT. That is a sentinel, not a core, and the extension map has
# to answer instead.
cat >"$FIXTURE/ra/playlists/Nintendo - Super Nintendo Entertainment System.lpl" <<LPL
{
  "version": "1.5",
  "default_core_path": "",
  "items": [
    {
      "path": "$FIXTURE/roms/Super Mario World (USA).sfc",
      "label": "Super Mario World",
      "core_path": "DETECT",
      "core_name": "DETECT"
    }
  ]
}
LPL
out=$(run_scan)
check "DETECT falls through to the extension map" \
  "snes9x" "$(jq -r '.games[0].coreName' <<<"$out")"

# A playlist pinned to one core outranks the extension map...
cat >"$FIXTURE/ra/playlists/Nintendo - Super Nintendo Entertainment System.lpl" <<LPL
{
  "version": "1.5",
  "default_core_path": "$FIXTURE/cores/gambatte_libretro.so",
  "items": [
    {
      "path": "$FIXTURE/roms/Super Mario World (USA).sfc",
      "label": "Super Mario World",
      "core_path": "DETECT"
    }
  ]
}
LPL
out=$(run_scan)
check "a playlist default core outranks the extension map" \
  "gambatte" "$(jq -r '.games[0].coreName' <<<"$out")"

# ...and a pinned entry outranks the playlist default.
cat >"$FIXTURE/ra/playlists/Nintendo - Super Nintendo Entertainment System.lpl" <<LPL
{
  "version": "1.5",
  "default_core_path": "$FIXTURE/cores/gambatte_libretro.so",
  "items": [
    {
      "path": "$FIXTURE/roms/Super Mario World (USA).sfc",
      "label": "Super Mario World",
      "core_path": "$FIXTURE/cores/snes9x_libretro.so"
    }
  ]
}
LPL
out=$(run_scan)
check "an entry's own core outranks the playlist default" \
  "snes9x" "$(jq -r '.games[0].coreName' <<<"$out")"

# A core named by a playlist that is not installed must not be launched.
cat >"$FIXTURE/ra/playlists/Nintendo - Super Nintendo Entertainment System.lpl" <<LPL
{
  "version": "1.5",
  "items": [
    {
      "path": "$FIXTURE/roms/Super Mario World (USA).sfc",
      "label": "Super Mario World",
      "core_path": "$FIXTURE/cores/uninstalled_libretro.so"
    }
  ]
}
LPL
out=$(run_scan)
check "a core that is not installed falls through instead of launching" \
  "snes9x" "$(jq -r '.games[0].coreName' <<<"$out")"

# Restore the playlist the later checks expect.
cat >"$FIXTURE/ra/playlists/Nintendo - Super Nintendo Entertainment System.lpl" <<LPL
{
  "version": "1.5",
  "items": [
    {
      "path": "$FIXTURE/roms/Super Mario World (USA).sfc",
      "label": "Super Mario World",
      "core_path": "$FIXTURE/cores/snes9x_libretro.so",
      "db_name": "Nintendo - Super Nintendo Entertainment System.lpl"
    }
  ]
}
LPL

# --- Malformed playlist ------------------------------------------------------

echo 'not json at all' >"$FIXTURE/ra/playlists/Broken.lpl"
out=$(run_scan)
check "a malformed playlist does not take the scan down with it" \
  "1" "$(jq '.games | length' <<<"$out")"

if (( failures )); then
  echo "scan-test: $passed passed, $failures failed"
  exit 1
fi
echo "scan-test: $passed passed"
