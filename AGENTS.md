# Arcade Plugin

## Verify Changes

- Run `./tests/run.sh` before considering a change complete. It is the CI entrypoint and requires `node`, `jq`, and Bash; `qmllint` is optional.
- Use `node tests/library-test.js` for `Library.js` changes and `bash tests/scan-test.sh` for scanner changes. The scanner test uses isolated RetroArch/core fixtures and does not touch the user's configuration.
- Run `bash -n bin/<script>` for a focused shell syntax check. Keep `bin/omarchy-arcade-*` executable.
- `qmllint` validates `Library.js`, `Overlay.qml`, `ArcadeLibrary.qml`, and every delegate file against the shell's type information; it cannot resolve the `qs.Ui.Panel` root in `Panel.qml`. `tests/panel-contract-test.sh` and `tests/qml-refs-test.js` cover the panel's runtime contract and undeclared `root.*` references, and `tests/seam-test.js` enforces the module map and surface size caps.

## Architecture

- Module map, enforced by `tests/seam-test.js`: QML views (`Panel.qml`, `Overlay.qml`, delegate files) import only `ArcadeSession.js`; `ArcadeSession.js` imports `Library.js`; `Library.js` imports nothing. Never call `Library.*` from QML.
- `Panel.qml` and `Overlay.qml` are separate shell entrypoints and object trees. They share disk state through `omarchy-arcade-scan`, `cores.conf`, and save states, not runtime QML state.
- `ArcadeLibrary.qml` is the shared library feed (scan process, fingerprint polling, parsing). Both surfaces instantiate it and own their own policy: the panel watches always, the overlay only while open. Scan fixes land in one place.
- Row/tile presentation lives in its own files (`ContinueRow.qml`, `LibraryRow.qml`, `GameTile.qml`, `InspectorCard.qml`, `KeyHintBar.qml`): props in, signals out, no data access, no launching. Keep it that way so qmllint can check them.
- `Library.js` must remain plain ES5-compatible, free of QML/Quickshell imports, and export its functions for Node tests. QML-only pragmas are stripped by `tests/library-test.js`.
- `ArcadeSession.js` is the pure orchestration seam shared by both QML surfaces; keep process/timer objects and navigation in QML, and keep session functions Node-testable.
- `bin/omarchy-arcade-scan` reads RetroArch playlists and streams tagged NDJSON lines to stdout — an internal first-seen document, then header, one `{"t":"game"}` line per game, and a trailer; playlist metadata is the library source. It forks jq once per playlist, streaming NUL-delimited fields, and its helpers return results through variables (`CORE_PATH`, `EXT`, `BOXART`, `STATE_INFO`) instead of stdout. Do not reintroduce per-ROM process spawns or `$( )` captures of these helpers: they cost ~7ms each and turned a 400-game scan from 150ms into seconds.
- Scan output is consumed incrementally: `ArcadeLibrary.qml` feeds `SplitParser` lines into a `Library.js` scan builder (`createScanBuilder`), so no surface ever holds the whole library as text — the shell is long-lived and a large library must never become one big allocation in it. Do not swap back to `StdioCollector` whole-document buffering. A `refresh()` during an in-flight scan is deferred (`rescanPending`), never a kill-and-restart, which keeps every `exited` signal paired with its own builder.
- Input and memory stay bounded by construction: the scanner caps every playlist-sourced field while building records, and `createScanBuilder` enforces per-record and total byte ceilings (`SCAN_LIMITS`) that fail closed with an explicit error. `normalizeGame` interns low-cardinality strings through a per-builder pool and never restates `rom` as `key`, so the retained model stays proportional to distinct data. Preserve all three when touching either side of the stream.
- The scanner's `--fingerprint` intentionally excludes the thumbnail tree: art appearing for an existing game changes no file a scan reads, and the periodic rescan picks it up. Re-adding that walk re-creates the dominant cold-cache poll cost.
- `bin/omarchy-arcade-launch` owns RetroArch invocation and playtime persistence. RetroArch runs in the background; INT/TERM are forwarded to it and its exit status propagates. Preserve that signal and status behavior.
- Atomic writes (plays.json, added.json, cores.conf) go through a temp file created in the destination directory, so the final `mv` is an atomic rename. A `/tmp` tempfile makes it a cross-filesystem copy, which is exactly the truncation risk the pattern exists to prevent.
- QML process commands use absolute paths. Plugin helpers resolve from `pluginDir`; Omarchy commands resolve from `$OMARCHY_PATH/bin` because detached processes do not inherit a login shell `PATH`.
- When changing launch behavior, update both QML surfaces or move it into `ArcadeSession.launchRequest` so launch arguments stay consistent.

## Runtime Fixtures

- Scanner behavior depends on `RA_CONFIG_DIR`, `XDG_STATE_HOME`, and `XDG_CONFIG_HOME`; use these variables with temporary directories for focused manual checks.
- The scanner requires `jq`. Playlist entries without an installed core should be skipped.

## Running Locally

- Marketplace rule: plugin folders must contain real files — no symlinks (folder or file level). The install is a real directory; after editing the repo run `./dev-sync.sh` to rsync it into `~/.config/omarchy/plugins/io.github.cgaray.arcade`, then `omarchy-restart-shell` (or `omarchy-shell shell rescanPlugins`) and confirm via the journal (`journalctl --user -t omarchy-shell`)."
- Quattro's GridView rejects grouped `section.*` assignments (first-party code only sections ListViews). Do not re-add section headers to the overlay grid without an upstream check.
- Drive it over IPC: `omarchy-shell io.github.cgaray.arcade toggle|refresh|status`, or summon the overlay with `omarchy-shell shell summon io.github.cgaray.arcade '{}'`.
- For a clean slate use `omarchy-restart-shell` (lock-safe, respawns via Hyprland). IPC can report "not responding" for a second during reload churn; retry rather than restarting.
- Shell logs land in the journal under the `omarchy-shell` tag: `journalctl --user -t omarchy-shell`. Plugin QML errors appear there.
