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
         "$FIXTURE/cores" "$FIXTURE/info" "$FIXTURE/roms" "$FIXTURE/state" "$FIXTURE/config"

# A core only has to exist; the scanner never loads it.
touch "$FIXTURE/cores/snes9x_libretro.so" "$FIXTURE/cores/gambatte_libretro.so"

# The .info files are the fixture's own, not the machine's: what a core claims
# to support is exactly what these tests are about, so reading the real
# /usr/share/libretro/info would make results depend on which cores the
# developer happens to have installed.
cat >"$FIXTURE/info/snes9x_libretro.info" <<INFO
display_name = "Nintendo - SNES / SFC (Snes9x)"
corename = "Snes9x"
systemname = "Super Nintendo Entertainment System"
supported_extensions = "smc|sfc|swc|fig"
INFO
cat >"$FIXTURE/info/gambatte_libretro.info" <<INFO
display_name = "Nintendo - Game Boy / Color (Gambatte)"
corename = "Gambatte"
systemname = "Game Boy"
supported_extensions = "gb|gbc|dmg"
INFO

cat >"$FIXTURE/ra/retroarch.cfg" <<CFG
libretro_directory = "$FIXTURE/cores"
libretro_info_path = "$FIXTURE/info"
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

# --- Extensionless ROMs ------------------------------------------------------

# Most of a downloaded collection has no extension at all, and `${rom##*.}` on
# a name with no dot returns the whole name -- which used to match nothing and
# drop the file silently. The folder is the hint, per the roms/<system>/
# convention.
mkdir -p "$FIXTURE/roms/snes" "$FIXTURE/roms/mystery"
touch "$FIXTURE/roms/snes/chronotrigger"
touch "$FIXTURE/roms/snes/donkeykongcountry"
out=$(run_scan)

check "an extensionless ROM under roms/snes/ is found" \
  "true" "$(jq '[.games[].title] | contains(["chronotrigger"])' <<<"$out")"

check "the folder decides its extension" \
  "sfc" "$(jq -r '.games[] | select(.title == "chronotrigger") | .ext' <<<"$out")"

check "and therefore its core" \
  "snes9x" "$(jq -r '.games[] | select(.title == "chronotrigger") | .coreName' <<<"$out")"

# An empty file in a folder that names no system, with nothing for libmagic to
# recognise, cannot be placed. It is left out rather than launched blind.
touch "$FIXTURE/roms/mystery/whatisthis"
out=$(run_scan)
check "an unplaceable extensionless file is skipped, not guessed" \
  "0" "$(jq '[.games[] | select(.title == "whatisthis")] | length' <<<"$out")"

check "a filename with no dot never becomes its own extension" \
  "0" "$(jq '[.games[] | select(.ext == "chronotrigger")] | length' <<<"$out")"

# A real extension still wins over the folder it happens to sit in.
touch "$FIXTURE/roms/snes/handheld.gb"
out=$(run_scan)
check "an explicit extension outranks the folder name" \
  "gb" "$(jq -r '.games[] | select(.title == "handheld") | .ext' <<<"$out")"

rm -rf "$FIXTURE/roms/snes" "$FIXTURE/roms/mystery"

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

# States in a core directory must not collide with a same-basename state for a
# different core. The core-specific state is newer and should win for Pinball.
mkdir -p "$FIXTURE/ra/states/Gambatte"
sleep 1
touch "$FIXTURE/ra/states/Gambatte/Pinball.state2"
out=$(run_scan)
check "core-specific states beat same-basename fallback states" \
  "2" "$(jq -r '.games[] | select(.title == "Pinball") | .resumeSlot' <<<"$out")"

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

# A library is normally part scanned and part not, so the two sources union.
# Suppressing the walk once a playlist existed hid every ROM the user had not
# imported yet -- which was most of them.
check "the walk still runs alongside a playlist" \
  "true" "$(jq '.meta.fromWalk > 0' <<<"$out")"

check "playlist entries are used" \
  "true" "$(jq '[.games[] | select(.title == "Super Mario World")] | length == 1' <<<"$out")"

check "unscanned ROMs are not hidden by a playlist" \
  "true" "$(jq '[.games[].title] | contains(["Pinball"])' <<<"$out")"

check "a ROM in both sources appears exactly once" \
  "true" "$(jq '.games | map(.rom) | (length == (unique | length))' <<<"$out")"

check "a playlist entry whose ROM is gone is dropped" \
  "0" "$(jq '[.games[] | select(.title == "Ghost Entry")] | length' <<<"$out")"

check "the playlist label wins over the filename" \
  "true" "$(jq '[.games[].title] | contains(["Super Mario World"]) and (contains(["Super Mario World (USA)"]) | not)' <<<"$out")"

check "box art is resolved from the playlist name" \
  "true" "$(jq -r '.games[] | select(.title == "Super Mario World") | (.art | endswith("Named_Boxarts/Super Mario World.png"))' <<<"$out")"

check "the system name comes from the playlist" \
  "Nintendo - Super Nintendo Entertainment System" \
  "$(jq -r '.games[] | select(.title == "Super Mario World") | .system' <<<"$out")"

# A walked ROM has no playlist to name its system, so it borrows the system
# RetroArch attributes to the core that will run it -- otherwise the library
# cannot be grouped or browsed by system at all.
check "a walked ROM takes its system from the core that runs it" \
  "Game Boy" "$(jq -r '.games[] | select(.title == "Pinball") | .system' <<<"$out")"

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
  "snes9x" "$(jq -r '.games[] | select(.title == "Super Mario World") | .coreName' <<<"$out")"

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
  "gambatte" "$(jq -r '.games[] | select(.title == "Super Mario World") | .coreName' <<<"$out")"

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
  "snes9x" "$(jq -r '.games[] | select(.title == "Super Mario World") | .coreName' <<<"$out")"

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
  "snes9x" "$(jq -r '.games[] | select(.title == "Super Mario World") | .coreName' <<<"$out")"

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
  "true" "$(jq '[.games[].title] | contains(["Super Mario World"])' <<<"$out")"

# --- Fingerprint -------------------------------------------------------------

# The panel polls this instead of rescanning, so it has to change whenever a
# scan would produce different output, and not otherwise.
fp() {
  RA_CONFIG_DIR="$FIXTURE/ra" \
  XDG_STATE_HOME="$FIXTURE/state" \
  XDG_CONFIG_HOME="$FIXTURE/config" \
  "$SCAN" --fingerprint
}

before=$(fp)
check "the fingerprint is stable when nothing changed" "$before" "$(fp)"

check "the fingerprint is not empty" "true" "$([[ -n $before ]] && echo true || echo false)"

touch "$FIXTURE/roms/Newly Added.sfc"
check "a new ROM changes the fingerprint" \
  "true" "$([[ $(fp) != "$before" ]] && echo true || echo false)"

before=$(fp)
rm -f "$FIXTURE/roms/Newly Added.sfc"
check "a removed ROM changes the fingerprint" \
  "true" "$([[ $(fp) != "$before" ]] && echo true || echo false)"

before=$(fp)
mkdir -p "$FIXTURE/ra/states/Snes9x"
touch "$FIXTURE/ra/states/Snes9x/Super Mario World (USA).state"
check "a new save state changes the fingerprint, so Continue updates" \
  "true" "$([[ $(fp) != "$before" ]] && echo true || echo false)"

before=$(fp)
printf 'gb = gambatte\n' >>"$FIXTURE/config/omarchy/arcade/cores.conf"
check "a core choice changes the fingerprint" \
  "true" "$([[ $(fp) != "$before" ]] && echo true || echo false)"

before=$(fp)
printf '# changed by test\n' >>"$FIXTURE/info/gambatte_libretro.info"
check "core metadata changes the fingerprint" \
  "true" "$([[ $(fp) != "$before" ]] && echo true || echo false)"

if (( failures )); then
  echo "scan-test: $passed passed, $failures failed"
  exit 1
fi
echo "scan-test: $passed passed"
