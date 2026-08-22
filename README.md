# Arcade

Your games in the Omarchy bar, each one showing the frame you paused on.
Press Enter and you are back inside it.

<p align="center">
  <img src="preview.png" alt="The Arcade bar panel: a Continue shelf of save-state thumbnails above the game library" width="380">
</p>

Press `b`, or right-click the bar icon, and the whole library opens as a wall
of cover art.

<p align="center">
  <img src="preview-overlay.png" alt="The Arcade overlay: a fullscreen grid of game cover art with system filters" width="820">
</p>

## Why this and not a game launcher

A launcher lists games. Arcade is built around the twenty seconds *after* you
decide to play — and around the desktop you are playing on top of.

- **Continue, not launch.** The top shelf is your save states, newest first,
  each showing the actual frame RetroArch captured when you saved. `Enter`
  resumes it. `f` starts the same game fresh.
- **Notifications go quiet** for the length of the game and come back after —
  including when the emulator crashes or is killed, because the restore waits
  for RetroArch to actually exit.
- **The screensaver stays away** during long cutscenes, then your idle setting
  is put back.
- **It restores what it found.** If you were already in do-not-disturb before
  launching, you are still in it afterwards. Arcade only undoes what it did.
- **It is themed.** Arcade draws from the same tokens as the rest of the shell,
  so it already matches whatever theme you run.

That middle group is the part a standalone launcher cannot do. It is the reason
this is an Omarchy plugin and not another window.

## Two surfaces, one plugin

Arcade ships a bar widget and a fullscreen overlay from the same plugin id.
They do different jobs:

| Surface | For |
|---|---|
| **Bar panel** | Picking up where you left off. The Continue shelf, search, and a resume in two keystrokes. |
| **Overlay** | Browsing. A hundred games as cover art, filtered by system. |

The shell instantiates the two entry points as separate object trees, so they
share nothing at runtime — and do not need to. Both run the same scanner and
read the same `cores.conf` and save states, so the disk is the shared state: a
core chosen in one is already in force in the other.

## Install

```bash
omarchy plugin add https://github.com/cgaray/omarchy-arcade.git --enable
```

Then add `io.github.cgaray.arcade` to your bar from **Omarchy menu → Settings → Bar**,
or by hand in `~/.config/omarchy/shell.json`:

```jsonc
{ "bar": { "layout": { "right": [ { "id": "io.github.cgaray.arcade" } ] } } }
```

Optionally bind them. In `~/.config/hypr/bindings.conf`:

```
bindd = SUPER, G, Arcade, exec, omarchy-shell io.github.cgaray.arcade toggle
# Toggle the fullscreen library: opens it, or dismisses it when already up --
# so the hotkey never reaches the window behind the overlay.
bindd = SUPER SHIFT, G, Arcade library, exec, omarchy-shell shell toggle io.github.cgaray.arcade '{}'
```

## Your library

Arcade reads RetroArch playlists from
`~/.config/retroarch/playlists/*.lpl`. RetroArch owns content scanning and
provides the title, system, core hint, and database name.

Scan new content in RetroArch. Arcade watches playlists, save states, and core
choices. Press `r` to refresh immediately.

The watch is a poll, not an inotify watch: the scanner has a `--fingerprint`
mode that signs the ROM tree in a few milliseconds, so the panel checks that
every ten seconds and only pays for a full rescan when it moves. That avoids
depending on `inotify-tools`, avoids exhausting the kernel's watch limit on a
large tree, and leaves no monitor process to keep alive across a shell
restart. Rescans themselves stay cheap — one jq pass per playlist, no
per-game process spawns — a few hundred milliseconds for a thousand games.

Box art comes from RetroArch's own thumbnail cache — Arcade downloads nothing.
Arcade records when each ROM first enters the library in
`~/.local/state/omarchy-arcade/added.json`; removing and later re-importing a
ROM keeps that original date.

### Browsing by system

Once a library spans more than one system, a filter row appears above it:
`All · 101`, `NES · 49`, `SNES · 52`. Click one, or press `s` to walk them.
Systems come from the playlist.

The fullscreen overlay can order the current wall by **Date added**, **Save
date**, **Last played**, or **Name**. Date added is persistent; existing
libraries establish their baseline on the first scan after upgrading.

## Which emulator runs a game

Every row shows it next to the system — `SNES · snes9x` — so the core is
visible before you press anything, not discovered when the emulator opens.

Arcade carries no table of opinions about which core is best. RetroArch ships
a `.info` file per core declaring what it supports, and that is the only
honest source for what your machine can actually run. Several cores usually
claim the same extension, and choosing between them is yours to make: the
**Cores** section at the bottom of the panel lists every extension in your
library that more than one installed core can open, with a dropdown of the
candidates. Picking one writes `~/.config/omarchy/arcade/cores.conf`, which
you can also edit by hand:

```
# one "ext = core" per line
sfc = snes9x
zip = mame
```

Note that a playlist usually does *not* answer the question. Scanning a
directory in RetroArch writes `"core_path": "DETECT"` on every entry, meaning
"decide at launch". The full order, most specific first:

1. **The core the playlist entry is pinned to**, if it is installed.
2. **The core the whole playlist is pinned to** (`default_core_path`).
3. **Your choice in `cores.conf`.**
4. **The first candidate** RetroArch's `.info` files offer, so the game is
   launchable while the choice is still outstanding.

A core named by a playlist but not installed falls through to the next choice.
Entries without a usable core are omitted.

## Keys

| Key | Does |
|---|---|
| `↑` `↓` | Move |
| `Enter` | Play, resuming the save state if there is one |
| `f` | Start fresh, ignoring the save state |
| `s` | Next system (`S` for previous) |
| `b` | Open the fullscreen library |
| `/` | Jump to search |
| `r` | Rescan |
| `Esc` | Clear the search, then close |

Right-click a row to start it fresh; left-click resumes. Right-clicking the
bar icon opens the fullscreen library on whatever system you were looking at;
middle-clicking rescans.

Both surfaces show a hint bar along the bottom that follows what you are
doing — browsing, filtering, or choosing a system — so the keys that work
right now are always visible without opening a help screen.

In the overlay, arrow keys move, `Tab` walks the systems (`Shift+Tab`
backwards), typing filters, and there is no search box to reach for — the
whole surface is one. `Ctrl+S` narrows to games with save states, and `?`
shows every shortcut.

## Settings

Configurable from the bar's widget settings, or inline in `shell.json`:

| Setting | Default | Does |
|---|---|---|
| `refreshIntervalSec` | 300 | Full rescan interval, as a safety net behind the watch. |
| `watchRoms` | true | Notice new ROMs, save states, and playlist imports without waiting. |
| `watchIntervalSec` | 10 | How often the cheap change-check runs. |
| `maxLibraryRows` | 40 | Caps rendered rows in the bar panel; search still covers everything. |
| `silenceNotifications` | true | Do-not-disturb for the length of the game. |
| `stayAwake` | true | Suppress idle and the lock screen while playing. |

## Layout

| Path | What |
|---|---|
| `Panel.qml` | The bar button and its popup: state, navigation, policy. |
| `Overlay.qml` | The fullscreen cover-art grid: state, navigation, policy. |
| `ArcadeLibrary.qml` | The shared library feed: scanning, fingerprint polling, parsing. |
| `ContinueRow.qml` / `LibraryRow.qml` | Panel shelf and list rows; presentation only. |
| `GameTile.qml` / `InspectorCard.qml` | Overlay tile and detail card; presentation only. |
| `KeyHintBar.qml` | Contextual keycap hints both surfaces show. |
| `bin/omarchy-arcade-cores` | Reads RetroArch's core `.info` files; records core choices. |
| `Library.js` | Filtering, ranking, Continue selection, system names. Pure, tested. |
| `ArcadeSession.js` | The one seam the views import: rebuilds the view model, formats display strings. Pure, tested. |
| `bin/omarchy-arcade-scan` | Builds the library as JSON; `--fingerprint` signs it cheaply. |
| `bin/omarchy-arcade-launch` | Launches a game and holds the desktop still. |

Both scripts run standalone:

```bash
./bin/omarchy-arcade-scan | jq '.games[0]'
./bin/omarchy-arcade-launch --core /usr/lib/libretro/snes9x_libretro.so \
                            --rom ~/Games/roms/game.sfc --slot 0
```

## Tests

```bash
./tests/run.sh
```

The suite validates the manifest, shell syntax, QML, plugin contracts, QML
references, library helpers, launcher behavior, and playlist scanning. Fixture
cores keep the scanner tests independent of the host system.

## Status

Working end to end: both surfaces, the Continue shelf with save-state
thumbnails, box art, search, per-system browsing, the core picker, playlist
scanning, and desktop integration. If RetroArch is not installed,
either surface says so and offers Omarchy's own installer.


## License

MIT
