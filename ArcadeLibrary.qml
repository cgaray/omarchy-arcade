import QtQuick
import Quickshell
import Quickshell.Io
import "ArcadeSession.js" as Session

// The library feed both surfaces consume. Each shell entrypoint instantiates
// its own copy -- the surfaces are separate object trees -- but the scan,
// fingerprint polling, and parsing live here exactly once, so a fix lands in
// both places at once.
//
// Surfaces own the policy: bind watchActive to decide when background
// polling runs, call refresh() to force a scan, and rebuild view state from
// your own properties inside changed().
Item {
  id: root

  property string pluginDir: ""
  // When false no fingerprint polls spawn; surfaces gate this on visibility
  // or on their own settings.
  property bool watchActive: false
  property int watchIntervalSec: 10

  property var games: []
  property var extensions: []
  property var scanMeta: ({})
  property string loadError: ""
  property bool scanning: false
  readonly property bool retroarchMissing: root.scanMeta.retroarchInstalled === false

  signal changed()

  property string lastFingerprint: ""

  // Scan state. The builder accumulates parsed rows as lines arrive, so no
  // part of this process ever holds the whole library as text. A refresh()
  // while a scan is already running never kills it: it is remembered and
  // rerun once the in-flight scan commits, which also means every exited
  // signal belongs to the builder that is still current.
  property var scanBuilder: null
  property bool rescanPending: false

  function refresh() {
    if (root.scanning) {
      root.rescanPending = true
      return
    }
    root.scanning = true
    root.scanBuilder = Session.createScanBuilder()
    scanProcess.running = true
  }

  function finishScan(exitCode) {
    var builder = root.scanBuilder
    root.scanBuilder = null
    root.scanning = false
    // A finished scan is itself the new baseline; comparing against a stale
    // fingerprint would only trigger an immediate duplicate rescan.
    root.lastFingerprint = ""
    var result = builder
      ? builder.finish()
      : { games: [], extensions: [], meta: {}, error: "scanner produced no output" }
    // An empty stream is the builder's error to report; anything else the
    // process says about itself is worth keeping too.
    if (!result.error && exitCode !== 0)
      result.error = "scanner exited with status " + exitCode
    root.loadError = result.error
    root.games = result.games
    root.extensions = result.extensions
    root.scanMeta = result.meta
    root.changed()
    if (root.rescanPending) {
      root.rescanPending = false
      root.refresh()
    }
  }

  Process {
    id: scanProcess
    command: [root.pluginDir + "/bin/omarchy-arcade-scan"]
    // Lines are parsed as they arrive. StdioCollector buffered the entire
    // library as one string before parsing, putting the whole document --
    // plus its parse tree -- inside the long-lived shell at once.
    stdout: SplitParser {
      onRead: function (line) {
        if (root.scanBuilder) root.scanBuilder.addLine(line)
      }
    }
    onExited: function (exitCode) { root.finishScan(exitCode) }
  }

  Process {
    id: watchProcess
    command: [root.pluginDir + "/bin/omarchy-arcade-scan", "--fingerprint"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = String(text || "").trim()
        if (!next.length) return
        // The first reading establishes a baseline rather than counting as a
        // change, so opening a surface does not immediately rescan twice.
        if (root.lastFingerprint === "") { root.lastFingerprint = next; return }
        if (!Session.fingerprintChanged(root.lastFingerprint, next)) return
        root.lastFingerprint = next
        root.refresh()
      }
    }
  }

  Timer {
    interval: Math.max(2, root.watchIntervalSec) * 1000
    running: root.watchActive
    repeat: true
    onTriggered: if (!watchProcess.running && !root.scanning) watchProcess.running = true
  }
}
