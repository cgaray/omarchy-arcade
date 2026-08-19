# Arcade Plugin

## Verify Changes

- Run `./tests/run.sh` before considering a change complete. It is the CI entrypoint and requires `node`, `jq`, and Bash; `qmllint` is optional.
- Use `node tests/library-test.js` for `Library.js` changes and `bash tests/scan-test.sh` for scanner changes. The scanner test uses isolated RetroArch/core fixtures and does not touch the user's configuration.
- Run `bash -n bin/<script>` for a focused shell syntax check. Keep `bin/omarchy-arcade-*` executable.
- `qmllint` can validate `Overlay.qml` and `Library.js` when installed, but cannot resolve the `qs.Ui.Panel` root in `Panel.qml`; `tests/panel-contract-test.sh` and `tests/qml-refs-test.js` cover the panel's runtime contract and undeclared `root.*` references.

## Architecture

- `Panel.qml` and `Overlay.qml` are separate shell entrypoints and object trees. They share disk state through `omarchy-arcade-scan`, `cores.conf`, and save states, not runtime QML state.
- `Library.js` must remain plain ES5-compatible, free of QML/Quickshell imports, and export its functions for Node tests. QML-only pragmas are stripped by `tests/library-test.js`.
- `ArcadeSession.js` is the pure orchestration seam shared by both QML surfaces; keep process/timer objects and navigation in QML, and keep session functions Node-testable.
- `bin/omarchy-arcade-scan` owns library discovery and emits one JSON document; playlist entries and the ROM walk are a union, with playlist metadata winning for duplicate ROM paths.
- `bin/omarchy-arcade-launch` owns RetroArch invocation, desktop-state suppression/restoration, and playtime persistence. Preserve its `trap`-based restoration on normal exit, failure, and signals.
- QML process commands use absolute paths. Plugin helpers resolve from `pluginDir`; Omarchy commands resolve from `$OMARCHY_PATH/bin` because detached processes do not inherit a login shell `PATH`.
- When changing scan or launch behavior, update both QML surfaces or deliberately centralize the shared behavior; Panel settings such as `romDir`, notification suppression, and idle suppression must not silently diverge from Overlay behavior.

## Runtime Fixtures

- Scanner behavior depends on `RA_CONFIG_DIR`, `XDG_STATE_HOME`, `XDG_CONFIG_HOME`, and optionally `ARCADE_ROM_DIR`; use these variables with temporary directories for focused manual checks.
- The scanner requires `jq`; extensionless ROM classification also uses directory conventions or `file`/libmagic. Missing or unmappable ROMs should be skipped rather than assigned a guessed core.
