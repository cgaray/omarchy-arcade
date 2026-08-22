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

  function refresh() {
    root.scanning = true
    scanProcess.running = false
    scanProcess.running = true
  }

  function applyScan(raw) {
    root.scanning = false
    // A finished scan is itself the new baseline; comparing against a stale
    // fingerprint would only trigger an immediate duplicate rescan.
    root.lastFingerprint = ""
    var parsed = Session.parseScan(raw)
    root.loadError = parsed.error
    root.games = parsed.games
    root.extensions = parsed.extensions
    root.scanMeta = parsed.meta
    root.changed()
  }

  Process {
    id: scanProcess
    command: [root.pluginDir + "/bin/omarchy-arcade-scan"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyScan(text)
    }
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
