# Arcade

Your games in the Omarchy bar, each one showing the frame you paused on.
Press Enter and you are back inside it.

<p align="center">
  <img src="preview.png" alt="The Arcade panel: a Continue shelf of save-state thumbnails above the game library" width="420">
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

## Install

```bash
omarchy plugin add https://github.com/cgaray/omarchy-arcade.git --enable
```

Then add `io.garay.arcade` to your bar from **Omarchy menu → Settings → Bar**,
or by hand in `~/.config/omarchy/shell.json`:

```jsonc
{ "bar": { "layout": { "right": [ { "id": "io.garay.arcade" } ] } } }
```

Optionally bind it. In `~/.config/hypr/bindings.conf`:

```
bindd = SUPER, G, Arcade, exec, omarchy-shell io.garay.arcade toggle
```

## Your library

Arcade reads two sources, in this order:

1. **RetroArch playlists** (`~/.config/retroarch/playlists/*.lpl`). If you have
   run RetroArch's scanner these win — they carry the real system name, the
   core RetroArch itself picked, and they unlock box art.
2. **A walk of your ROM folder**, `~/Games/roms` on a stock Omarchy install.
   The fallback for a fresh setup, where the extension picks the core.

Drop ROMs in `~/Games/roms` and press `r`. That is the whole setup.

Box art comes from RetroArch's own thumbnail cache — Arcade downloads nothing.

### Extensions Arcade will not guess at

`.bin`, `.iso`, and `.zip` belong to several systems each, and RetroArch given
the wrong core does not fail cleanly: it opens a black window and sits there.
So the ROM walk skips ambiguous extensions instead of guessing.

If your library is unambiguous, claim them in
`~/.config/omarchy/arcade/cores.conf`:

```
# one "ext = core" per line
zip = snes9x
bin = mednafen_psx_hw
```

Playlists are unaffected — they already name their own core.

## Keys

| Key | Does |
|---|---|
| `↑` `↓` | Move |
| `Enter` | Play, resuming the save state if there is one |
| `f` | Start fresh, ignoring the save state |
| `/` | Jump to search |
| `r` | Rescan |
| `Esc` | Clear the search, then close |

Right-click a row to start it fresh; left-click resumes.

## Settings

Configurable from the bar's widget settings, or inline in `shell.json`:

| Setting | Default | Does |
|---|---|---|
| `refreshIntervalSec` | 300 | Background rescan interval. Opening the panel always rescans. |
| `maxLibraryRows` | 40 | Caps rendered rows; search still covers everything. |
| `silenceNotifications` | true | Do-not-disturb for the length of the game. |
| `stayAwake` | true | Suppress idle and the lock screen while playing. |
| `romDir` | "" | Override RetroArch's browser directory. |

## Layout

| Path | What |
|---|---|
| `Panel.qml` | The bar button and its popup. All UI. |
| `Library.js` | Filtering, ranking, Continue selection, system names. Pure, tested. |
| `bin/omarchy-arcade-scan` | Builds the library as JSON. |
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

Manifest validation, `bash -n`, `qmllint`, 20 unit tests over `Library.js`, and
25 integration tests that run the scanner against a fixture library — including
save states in per-core subdirectories, dead playlist entries, malformed
playlists, and filenames with spaces and apostrophes. No display, no running
shell, no emulator.

## Status

Early, but working end to end: the bar widget, the Continue shelf with save
state thumbnails, box art, search, both library sources, and the desktop
integration.

Not yet: Steam, Lutris, and Heroic as additional sources — the scanner is
shaped for them, each being a function that appends to the same record shape.

## License

MIT
