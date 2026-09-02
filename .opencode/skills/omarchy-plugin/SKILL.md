---
name: omarchy-plugin
description: Use when creating, reviewing, or security-hardening an Omarchy Quickshell plugin, especially work involving manifest.json, QML surfaces, Bash helpers, marketplace submissions, bounded input, or plugin tests.
---

# Omarchy Plugin Engineering

Use this skill for end-to-end plugin work. Read the repository's `AGENTS.md`
first when one exists; it is the project-specific source of truth and takes
precedence over these general rules.

## First Inspect

- Identify the plugin manifest, entrypoints, QML files, helper scripts, tests,
  README, and license before editing.
- Check `git status` and preserve unrelated user changes.
- Find the repository's CI entrypoint and run the narrowest relevant tests
  during iteration, then the complete suite before finishing.
- Treat marketplace validation as structural and compatibility checking, not a
  security audit.

## Plugin Shape

- Keep `manifest.json` valid, uniquely identified, and consistent with the
  repository's declared entrypoints and version.
- Keep installation and removal instructions, license, runtime dependencies,
  and required host applications documented in the root `README.md`.
- Use real files, not file or directory symlinks; marketplace installs must be
  self-contained after checkout.
- Do not add install hooks, privilege escalation, network access, telemetry, or
  bundled dependencies without an explicit, documented requirement.
- Resolve plugin-local helpers from `pluginDir`; resolve Omarchy commands from
  `$OMARCHY_PATH/bin` because detached processes do not inherit a login-shell
  `PATH`.
- Keep writes narrowly scoped, explicit, and atomic. Write temporary files in
  the destination directory before `mv`; never use `/tmp` for a file that will
  be renamed into another filesystem.

## QML Architecture

- Keep shell entrypoints separate when the host creates separate object trees;
  share disk state through the documented helper contracts, not runtime QML
  globals.
- Preserve the module map: QML imports the orchestration seam, the orchestration
  seam imports the pure library layer, and the pure library layer imports
  nothing from QML or Quickshell.
- Keep presentation delegates prop-in/signal-out. They must not read library
  state, launch processes, or perform data access.
- Keep process and timer objects, navigation, and surface policy in QML; keep
  pure orchestration functions testable from Node where the project uses that
  seam.
- Follow the host shell's actual component contracts. Do not assume generic
  Qt/QML behavior, especially for GridView sections, panel roots, or IPC.
- Prefer incremental process parsing. Do not replace a line parser with a
  whole-document collector for unbounded user libraries.
- If two surfaces launch the same helper, centralize the request or update both
  surfaces and test their arguments together.

## Shell And Data Boundaries

- Assume every RetroArch playlist, config, core metadata file, save-state tree,
  and JSON state file is user-controlled and potentially malformed, huge,
  replaced, a symlink, or a FIFO.
- Apply bounds while building collections, not after an array, string, or parser
  has already consumed it. Bound item counts, directory depth, record fields,
  total output, and whole-file input bytes.
- Read replaceable files through one descriptor opened with
  `O_NOFOLLOW|O_NONBLOCK`, verify that descriptor is a regular file, and stream
  only the allowed bytes from that descriptor into the parser. Never `stat` a
  pathname and reopen it, and never use pathname-based `head -c` for a security
  boundary.
- Reject or safely skip malformed input without deleting or resetting valid
  persisted state. A truncated JSON document should fail closed and leave the
  existing file untouched.
- Bound recursive walks by depth, entry count, and time. Bound the complete
  process with a hard deadline because a child such as `find` or `jq` can block
  before a shell loop checks its soft deadline.
- Serialize competing scans and state writers with bounded exclusive locks.
  Waiting for a healthy concurrent operation is preferable to racing; abandon
  a wedged lock holder after the defined wait.
- Preserve framed stream integrity: emit matching header/game/trailer counts,
  detect interrupted streams, and report truncation explicitly rather than
  presenting partial data as an empty library.
- Keep low-cardinality strings interned in retained models and avoid storing
  duplicate fields such as a key that merely repeats a ROM path.
- Avoid per-item process spawns and command substitutions in hot loops. Return
  helper results through variables or a bounded stream, and preserve delimiter
  choices that cannot collapse empty fields.

## Security Review

Review findings first, ordered by severity, with file and line references.
Check at least:

- Arbitrary command execution through unquoted paths, shell interpolation,
  `eval`, unsafe `sed` expressions, or user-controlled command arguments.
- Symlink, FIFO, device, and check-then-use races on every file read.
- Unbounded allocations in QML collectors, JSON parsing, shell variables,
  arrays, associative arrays, `jq` reductions, and newline-free records.
- Unbounded filesystem traversal, per-entry process spawning, lock waits, and
  child processes without a deadline or process-group cleanup.
- Writes outside the documented state/config locations, non-atomic writes,
  accidental overwrites, and read-modify-write races.
- Signal forwarding and exit-status handling for launched applications.
  Record usage or mutate state only on the intended successful status.
- Network, privilege, install-hook, telemetry, and bundled dependency changes.
- QML import-layer violations, undeclared `root.*` references, host contract
  violations, and inconsistent behavior between shell surfaces.
- Tests for malformed, oversized, replaced, symlinked, FIFO, concurrent, and
  interrupted inputs. Do not claim a security fix without a regression test or
  a documented reason a focused test is impractical.

## Verification

- Run the repository's CI entrypoint, commonly `./tests/run.sh`.
- For library changes, run the repository's Node library test; for scanner or
  launcher changes, run their focused shell integration tests.
- Run `bash -n` on every Bash helper and preserve executable bits on
  `bin/omarchy-arcade-*` scripts.
- Run `qmllint` where the host type information supports it. Use repository
  contract and reference tests for host roots that `qmllint` cannot resolve.
- Test runtime behavior with isolated `RA_CONFIG_DIR`, `XDG_STATE_HOME`, and
  `XDG_CONFIG_HOME` fixtures. Never use the user's RetroArch or Omarchy state
  for tests.
- For local shell integration, sync only when requested or needed, then use
  `omarchy-restart-shell` or the host's plugin rescan command and inspect the
  `omarchy-shell` journal for QML/runtime errors.
- Inspect `git diff --check`, `git status`, and the final diff. Do not commit,
  push, or create a marketplace submission unless explicitly requested.

## Marketplace Response

When preparing a submission or responding to reviewer comments:

- Pin the exact commit being offered for validation.
- Separate automated validation from manual security findings.
- Address the full data path, not only the final retained model: source walk,
  file open, parser input, intermediate collection, emitted stream, and QML
  model.
- State what changed, what remains bounded, what tests passed, and any honest
  residual limitation. Avoid claiming that a marketplace validation or a
  deterministic baseline is a security audit.
