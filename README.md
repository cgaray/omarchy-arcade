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
  including when the emulator crashes, because the restore runs from a trap.
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

Then add `io.garay.arcade` to your bar from **Omarchy menu → Settings → Bar**,
or by hand in `~/.config/omarchy/shell.json`:

```jsonc
{ "bar": { "layout": { "right": [ { "id": "io.garay.arcade" } ] } } }
```

Optionally bind them. In `~/.config/hypr/bindings.conf`:

```
bindd = SUPER, G, Arcade, exec, omarchy-shell io.garay.arcade toggle
bindd = SUPER SHIFT, G, Arcade library, exec, omarchy-shell shell summon io.garay.arcade '{}'
```

## Your library

Arcade reads two sources, in this order:

1. **RetroArch playlists** (`~/.config/retroarch/playlists/*.lpl`), which carry
   the real title, the system name, and box art.
2. **A walk of your ROM folder**, `~/Games/roms` on a stock Omarchy install,
   including subfolders.

The two are a union, not a fallback. Importing content into RetroArch is
something people do a few games at a time, so a library is normally part
scanned and part not — letting a playlist suppress the walk would hide every
ROM you had not got round to importing. A ROM in both keeps the playlist's
better metadata and appears once.

Drop ROMs in `~/Games/roms` and they appear on their own — Arcade watches the
folder, along with your save states, playlists, and core choices. `r` forces a
rescan if you would rather not wait.

The watch is a poll, not an inotify watch: the scanner has a `--fingerprint`
mode that signs the ROM tree in a few milliseconds, so the panel checks that
every ten seconds and only pays for a full rescan when it moves. That avoids
depending on `inotify-tools`, avoids exhausting the kernel's watch limit on a
large tree, and leaves no monitor process to keep alive across a shell
restart.

Box art comes from RetroArch's own thumbnail cache — Arcade downloads nothing.

### ROMs with no extension

Most of a collection downloaded as a set has no file extension at all. Arcade
places those two ways: the folder they sit in, following the `roms/<system>/`
convention, and failing that libmagic, which recognises most ROM images by
content. A file neither can place is left out.

For a squashed filename like `thelegendofzeldaalinktothepast`, Arcade reads
the name out of the ROM header instead — `The Legend of Zelda`. A filename
someone clearly typed is never overwritten.

### Browsing by system

Once a library spans more than one system, a filter row appears above it:
`All · 101`, `NES · 49`, `SNES · 52`. Click one, or press `s` to walk them.
Systems come from the playlist where there is one, and otherwise from the
system RetroArch attributes to the core that will run the game.

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

A core named by a playlist but not installed falls through instead of failing
at launch, and a ROM nothing can place is left out rather than guessed at.

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

In the overlay, arrow keys move, `Tab` walks the systems, typing filters, and
there is no search box to reach for — the whole surface is one.

## Settings

Configurable from the bar's widget settings, or inline in `shell.json`:

| Setting | Default | Does |
|---|---|---|
| `refreshIntervalSec` | 300 | Full rescan interval, as a safety net behind the watch. |
| `watchRoms` | true | Notice new ROMs, save states, and playlist imports without waiting. |
| `watchIntervalSec` | 10 | How often the cheap change-check runs. |
| `maxLibraryRows` | 40 | Caps rendered rows; search still covers everything. |
| `silenceNotifications` | true | Do-not-disturb for the length of the game. |
| `stayAwake` | true | Suppress idle and the lock screen while playing. |
| `romDir` | "" | Override RetroArch's browser directory. |

## Layout

| Path | What |
|---|---|
| `Panel.qml` | The bar button and its popup. |
| `Overlay.qml` | The fullscreen cover-art grid. |
| `bin/omarchy-arcade-cores` | Reads RetroArch's core `.info` files; records core choices. |
| `Library.js` | Filtering, ranking, Continue selection, system names. Pure, tested. |
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

Manifest validation, `bash -n`, `qmllint` on `Library.js` and `Overlay.qml`, a
plugin contract
check, 49 unit tests over `Library.js`, and 44 integration tests that run the
scanner against a fixture library — including the full core-precedence chain,
`DETECT` entries, uninstalled cores, extensionless ROMs, save states in
per-core subdirectories, dead playlist entries, malformed playlists, and
filenames with spaces and apostrophes. The fixture ships its own `.info` files
so results do not depend on which cores the machine happens to have. No
display, no running shell, no emulator.

## Status

Early, but working end to end: both surfaces, the Continue shelf with save
state thumbnails, box art, search, per-system browsing, the core picker, both
library sources, and the desktop integration. If RetroArch is not installed,
either surface says so and offers Omarchy's own installer.

Not yet: Steam, Lutris, and Heroic as additional sources — the scanner is
shaped for them, each being a function that appends to the same record shape.

## License

MIT
