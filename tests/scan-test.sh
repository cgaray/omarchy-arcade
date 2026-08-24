#!/bin/bash

# Integration test for omarchy-arcade-scan against a fixture library.
#
# Builds a throwaway RetroArch config and fake cores, then checks scanner JSON.

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

# The scanner streams tagged NDJSON rather than one document. Reassemble that
# into the single object most assertions below were written against, and pin
# the wire format itself with dedicated checks.
collect_library() {
  jq -cs '
    map(select(.t == "game") | .g) as $games
    | (map(select(.t == "trailer")) | first // {}) as $tail
    | { games: $games,
        extensions: ($tail.extensions // []),
        meta: ($tail.meta // {}) }'
}

scan_lib() {
  run_scan | collect_library
}

# --- Playlist source ---------------------------------------------------------

cat >"$FIXTURE/ra/playlists/Nintendo - Super Nintendo Entertainment System.lpl" <<LPL
{
  "version": "1.5",
  "items": [
    { "path": "$FIXTURE/roms/Super Mario World (USA).sfc", "label": "Super Mario World", "core_path": "DETECT" },
    { "path": "$FIXTURE/roms/Tom's Adventure.sfc", "label": "Tom's Adventure", "core_path": "DETECT" }
  ]
}
LPL
cat >"$FIXTURE/ra/playlists/Nintendo - Game Boy.lpl" <<LPL
{
  "version": "1.5",
  "items": [
    { "path": "$FIXTURE/roms/Pinball.gb", "label": "Pinball", "core_path": "DETECT" }
  ]
}
LPL

raw=$(run_scan) || { echo "FAIL: scanner exited non-zero"; exit 1; }

out=$(collect_library <<<"$raw")
jq -e . >/dev/null 2>&1 <<<"$out" || { echo "FAIL: scanner did not emit valid JSON"; exit 1; }
passed=$((passed + 1))

stream_json_ok=true
while IFS= read -r stream_line; do
  jq -e . >/dev/null 2>&1 <<<"$stream_line" || { stream_json_ok=false; break; }
done <<<"$raw"
check "every line of the stream is valid JSON" "true" "$stream_json_ok"

check "the stream opens with a header" \
  "header" "$(sed -n '1p' <<<"$raw" | jq -r '.t')"

check "the added-state document never reaches stdout" \
  "0" "$(grep -c '"t":"added"' <<<"$raw" || true)"

check "the stream frames exactly the games it carries" \
  "$(( $(jq '.games | length' <<<"$out") + 2 ))" \
  "$(wc -l <<<"$raw" | tr -d ' ')"

check "playlist entries form the library" \
  "3" "$(jq '.games | length' <<<"$out")"

check "unmapped extensions are skipped" \
  "0" "$(jq '[.games[] | select(.title == "notes")] | length' <<<"$out")"

check "ambiguous .zip is skipped rather than guessed" \
  "0" "$(jq '[.games[] | select(.title == "arcade-set")] | length' <<<"$out")"

check "playlist labels define titles" \
  "true" "$(jq '[.games[].title] | contains(["Super Mario World"])' <<<"$out")"

check "an apostrophe in a filename survives" \
  "true" "$(jq '[.games[].title] | contains(["Tom'"'"'s Adventure"])' <<<"$out")"

check "DETECT entries resolve through the core map" \
  "gambatte" "$(jq -r '.games[] | select(.title == "Pinball") | .coreName' <<<"$out")"

check "games are sorted by title" \
  "true" "$(jq '[.games[].title] == ([.games[].title] | sort_by(ascii_downcase))' <<<"$out")"

check "playlist games start with no resume" \
  "0" "$(jq '[.games[] | select(.resumeAt > 0)] | length' <<<"$out")"

first_added=$(jq '.games[] | select(.title == "Super Mario World") | .addedAt' <<<"$out")
check "games receive a first-discovered timestamp" \
  "true" "$([[ $first_added -gt 0 ]] && echo true || echo false)"

out=$(scan_lib)
check "the first-discovered timestamp survives later scans" \
  "$first_added" "$(jq '.games[] | select(.title == "Super Mario World") | .addedAt' <<<"$out")"

check "added dates are persisted as valid JSON state" \
  "true" "$(jq -e 'type == "object"' "$FIXTURE/state/omarchy-arcade/added.json" >/dev/null 2>&1 && echo true || echo false)"


# --- Save states -------------------------------------------------------------

touch "$FIXTURE/ra/states/Pinball.state"
touch "$FIXTURE/ra/states/Pinball.state.png"
out=$(scan_lib)

check "a save state produces a resume slot" \
  "0" "$(jq -r '.games[] | select(.title == "Pinball") | .resumeSlot' <<<"$out")"

check "the state thumbnail is found" \
  "true" "$(jq -r '.games[] | select(.title == "Pinball") | (.resumeArt | endswith("Pinball.state.png"))' <<<"$out")"

check "resumeAt is a real timestamp" \
  "true" "$(jq '.games[] | select(.title == "Pinball") | .resumeAt > 0' <<<"$out")"

# The auto state is newer, so it should win the slot.
sleep 1
touch "$FIXTURE/ra/states/Pinball.state.auto"
out=$(scan_lib)
check "the newest state wins, including the auto slot" \
  "auto" "$(jq -r '.games[] | select(.title == "Pinball") | .resumeSlot' <<<"$out")"

# Every state the game has is reported, newest first, so the inspector can
# offer a choice instead of only the winner.
pinball_slots="$(jq -r '.games[] | select(.title == "Pinball") | .slots' <<<"$out")"
check "all slots are emitted newest first" \
  "auto" "${pinball_slots%%:*}"
check "the older slot is still listed" \
  "true" "$([[ $pinball_slots == *'0:'* ]] && echo true || echo false)"

# RetroArch's sort_savestates_enable puts states in a per-core subdirectory,
# so the scanner has to find them below the configured directory, not in it.
mkdir -p "$FIXTURE/ra/states/Snes9x"
sleep 1
touch "$FIXTURE/ra/states/Snes9x/Super Mario World (USA).state1"
touch "$FIXTURE/ra/states/Snes9x/Super Mario World (USA).state1.png"
out=$(scan_lib)

check "states in a per-core subdirectory are found" \
  "1" "$(jq -r '.games[] | select(.title == "Super Mario World") | .resumeSlot' <<<"$out")"

check "a subdirectory state's thumbnail is found" \
  "true" "$(jq -r '.games[] | select(.title == "Super Mario World") | (.resumeArt | endswith(".state1.png"))' <<<"$out")"

# States in a core directory must not collide with a same-basename state for a
# different core. The core-specific state is newer and should win for Pinball.
mkdir -p "$FIXTURE/ra/states/Gambatte"
sleep 1
touch "$FIXTURE/ra/states/Gambatte/Pinball.state2"
out=$(scan_lib)
check "core-specific states beat same-basename fallback states" \
  "2" "$(jq -r '.games[] | select(.title == "Pinball") | .resumeSlot' <<<"$out")"

check "a state thumbnail is never mistaken for a state" \
  "0" "$(jq '[.games[] | select(.resumeSlot | tostring | endswith("png"))] | length' <<<"$out")"

# --- cores.conf override -----------------------------------------------------

mkdir -p "$FIXTURE/config/omarchy/arcade"
cat >"$FIXTURE/config/omarchy/arcade/cores.conf" <<CONF
zip = snes9x
CONF
cat >"$FIXTURE/ra/playlists/Ambiguous.lpl" <<LPL
{
  "version": "1.5",
  "items": [
    { "path": "$FIXTURE/roms/arcade-set.zip", "label": "arcade-set", "core_path": "DETECT" }
  ]
}
LPL
out=$(scan_lib)
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

out=$(scan_lib)


check "playlist entries are used" \
  "true" "$(jq '[.games[] | select(.title == "Super Mario World")] | length == 1' <<<"$out")"

check "ROMs absent from playlists are hidden" \
  "false" "$(jq '[.games[].title] | contains(["notes"])' <<<"$out")"

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

check "a playlist entry supplies its system" \
  "Nintendo - Game Boy" "$(jq -r '.games[] | select(.title == "Pinball") | .system' <<<"$out")"

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
out=$(scan_lib)
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
out=$(scan_lib)
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
out=$(scan_lib)
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
out=$(scan_lib)
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

# --- Field caps ----------------------------------------------------------------

# Playlist metadata is user-editable text; every sourced field is capped while
# records are built, so a pathological label cannot balloon a streamed record
# -- or the model built from it.
printf -v LONG_LABEL 'a%.0s' {1..8000}
cat >"$FIXTURE/ra/playlists/Nintendo - Game Boy.lpl" <<LPL
{
  "version": "1.5",
  "items": [
    { "path": "$FIXTURE/roms/Pinball.gb", "label": "$LONG_LABEL", "core_path": "DETECT" }
  ]
}
LPL
out=$(scan_lib)
check "an oversized label truncates instead of ballooning the record" \
  "512" "$(jq --arg rom "$FIXTURE/roms/Pinball.gb" \
           '[.games[] | select(.rom == $rom)][0].title | length' <<<"$out")"

# Restore what later sections expect from this playlist.
cat >"$FIXTURE/ra/playlists/Nintendo - Game Boy.lpl" <<LPL
{
  "version": "1.5",
  "items": [
    { "path": "$FIXTURE/roms/Pinball.gb", "label": "Pinball", "core_path": "DETECT" }
  ]
}
LPL

# --- Malformed playlist ------------------------------------------------------

echo 'not json at all' >"$FIXTURE/ra/playlists/Broken.lpl"
out=$(scan_lib)
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

touch "$FIXTURE/ra/playlists/New.lpl"
check "a new playlist changes the fingerprint" \
  "true" "$([[ $(fp) != "$before" ]] && echo true || echo false)"

before=$(fp)
rm -f "$FIXTURE/ra/playlists/New.lpl"
check "a removed playlist changes the fingerprint" \
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

# A game discovered by a later scan receives a newer timestamp without
# changing the date of games already known to the library.
sleep 1
touch "$FIXTURE/roms/Later Addition.gb"
cat >"$FIXTURE/ra/playlists/Added.lpl" <<LPL
{
  "version": "1.5",
  "items": [
    { "path": "$FIXTURE/roms/Later Addition.gb", "label": "Later Addition", "core_path": "DETECT" }
  ]
}
LPL
out=$(scan_lib)
later_added=$(jq '.games[] | select(.title == "Later Addition") | .addedAt' <<<"$out")
check "newly discovered games receive a newer added date" \
  "true" "$([[ $later_added -gt $first_added ]] && echo true || echo false)"
check "adding another game does not rewrite an existing added date" \
  "$first_added" "$(jq '.games[] | select(.title == "Super Mario World") | .addedAt' <<<"$out")"

# --- Bounds ------------------------------------------------------------------

# Every collection the scanner builds is capped while it is built, so a large
# or malformed RetroArch tree costs a truncated scan and a note on stderr
# rather than unbounded CPU, memory and wall clock. Each cap is exercised by
# lowering it to something a fixture can reach.

bounded_scan() {
  env RA_CONFIG_DIR="$FIXTURE/ra" \
      XDG_STATE_HOME="$FIXTURE/state" \
      XDG_CONFIG_HOME="$FIXTURE/config" \
      "$@" "$SCAN"
}

capped=$(bounded_scan OMARCHY_ARCADE_MAX_GAMES=1 2>/dev/null)
capped_status=$?
check "a capped scan exits cleanly rather than failing" "0" "$capped_status"
check "the game cap bounds the library" \
  "1" "$(grep -c '"t":"game"' <<<"$capped")"
check "a capped stream is still framed by a trailer" \
  "trailer" "$(tail -n1 <<<"$capped" | jq -r '.t')"
check "the header still counts exactly the games that follow" \
  "1" "$(head -n1 <<<"$capped" | jq -r '.games')"
check "the game cap says so on stderr" \
  "true" "$(bounded_scan OMARCHY_ARCADE_MAX_GAMES=1 2>&1 >/dev/null \
            | grep -qF 'reached the 1-game limit' && echo true || echo false)"

# The save-state walk is the one a user can grow without limit, so it stops
# at a file count instead of enumerating whatever is there.
limited=$(bounded_scan OMARCHY_ARCADE_MAX_STATE_FILES=1 2>/dev/null)
check "a capped save-state walk still produces a library" \
  "trailer" "$(tail -n1 <<<"$limited" | jq -r '.t')"
check "the save-state cap says so on stderr" \
  "true" "$(bounded_scan OMARCHY_ARCADE_MAX_STATE_FILES=1 2>&1 >/dev/null \
            | grep -qF 'save-state limit' && echo true || echo false)"

# jq parses a playlist whole, so one larger than the input cap is skipped
# before it is read -- and skipping it costs its own entries, not the scan.
{ printf '{"items":['; head -c 200000 /dev/zero | tr '\0' ' '; printf ']}'; } \
  >"$FIXTURE/ra/playlists/Huge.lpl"
check "an oversized playlist is skipped rather than parsed" \
  "true" "$(bounded_scan OMARCHY_ARCADE_MAX_JSON_BYTES=8192 2>&1 >/dev/null \
            | grep -qF 'Huge.lpl' && echo true || echo false)"
check "skipping an oversized playlist leaves the rest of the library" \
  "true" "$(bounded_scan OMARCHY_ARCADE_MAX_JSON_BYTES=8192 2>/dev/null \
            | collect_library | jq '[.games[].title] | contains(["Pinball"])')"
rm -f "$FIXTURE/ra/playlists/Huge.lpl"

# A cap that accepts zero is a cap a stray empty variable turns off, so an
# override that is not a positive number falls back to the default.
full_count=$(scan_lib | jq '.games | length')
check "a zero cap override is ignored, not obeyed" \
  "$full_count" \
  "$(bounded_scan OMARCHY_ARCADE_MAX_GAMES=0 2>/dev/null | collect_library | jq '.games | length')"
check "a non-numeric cap override is ignored, not obeyed" \
  "$full_count" \
  "$(bounded_scan OMARCHY_ARCADE_MAX_GAMES=nonsense 2>/dev/null | collect_library | jq '.games | length')"

# The walk descends a bounded number of levels: RetroArch's deepest layout is
# states/<core>/<content>/<file>, and a tree deeper than that is not followed
# to the bottom by the scan -- nor, so the two stay consistent, by the
# fingerprint that decides when to rescan.
before_slot=$(scan_lib | jq -r '.games[] | select(.title == "Pinball") | .resumeSlot')
before=$(fp)
sleep 1
mkdir -p "$FIXTURE/ra/states/Gambatte/deep/deeper/deepest"
touch "$FIXTURE/ra/states/Gambatte/deep/deeper/deepest/Pinball.state9"
check "a save state past the depth cap is not indexed" \
  "$before_slot" \
  "$(scan_lib | jq -r '.games[] | select(.title == "Pinball") | .resumeSlot')"
check "a save state past the depth cap does not move the fingerprint" \
  "$before" "$(fp)"

# The deadline covers the wait for another scan's lock as well as the work:
# a scan wedged holding it must not park every later caller forever.
mkdir -p "$FIXTURE/state/omarchy-arcade"
flock -x "$FIXTURE/state/omarchy-arcade/.scan.lock" -c 'sleep 3' &
lock_holder=$!
sleep 0.3
bounded_scan OMARCHY_ARCADE_DEADLINE=1 >/dev/null 2>&1
check "a scan gives up on a held lock instead of waiting on it forever" "1" "$?"
wait "$lock_holder" 2>/dev/null

# --- Concurrent scans ----------------------------------------------------------

# The panel and the overlay each run this script. Overlapping invocations
# wait on a state-dir lock instead of racing through the same playlists and
# interleaving added.json writers.
run_scan >"$FIXTURE/concurrent-a.json" &
scan_a=$!
run_scan >"$FIXTURE/concurrent-b.json" &
scan_b=$!
wait "$scan_a" "$scan_b"

check "the first concurrent scan streams to completion" \
  "trailer" "$(tail -n1 "$FIXTURE/concurrent-a.json" | jq -r '.t')"
check "the second concurrent scan streams to completion" \
  "trailer" "$(tail -n1 "$FIXTURE/concurrent-b.json" | jq -r '.t')"

check "concurrent scans agree on the library size" \
  "$(collect_library <"$FIXTURE/concurrent-a.json" | jq '.games | length')" \
  "$(collect_library <"$FIXTURE/concurrent-b.json" | jq '.games | length')"

check "concurrent scans agree on first-discovered dates" \
  "$(collect_library <"$FIXTURE/concurrent-a.json" | jq -S '.games | map(.addedAt)')" \
  "$(collect_library <"$FIXTURE/concurrent-b.json" | jq -S '.games | map(.addedAt)')"

# --- retroarch.cfg in the fingerprint ------------------------------------------

# Only the five path keys a scan reads belong here. RetroArch rewrites the
# whole config on nearly any GUI settings change, and none of that should
# trigger rescans; a genuine directory move must. These checks run last
# because appending a duplicate key re-points the fixture's own scans.
before=$(fp)
printf '\nvideo_shader = "none"\n' >>"$FIXTURE/ra/retroarch.cfg"
check "unrelated retroarch.cfg edits do not change the fingerprint" \
  "$before" "$(fp)"

printf '\nplaylist_directory = "%s/x"\n' "$FIXTURE" >>"$FIXTURE/ra/retroarch.cfg"
check "moving a directory a scan reads changes the fingerprint" \
  "true" "$([[ $(fp) != "$before" ]] && echo true || echo false)"

if (( failures )); then
  echo "scan-test: $passed passed, $failures failed"
  exit 1
fi
echo "scan-test: $passed passed"
