import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Library.js" as Library

// Arcade lives in the bar because that is where you are when you decide to
// stop working. The panel's whole argument is the Continue shelf: every row
// carries the frame RetroArch captured when you saved, so you are picking a
// memory rather than reading a list of filenames.
Panel {
  id: root
  moduleName: "io.garay.arcade"
  ipcTarget: "io.garay.arcade"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/io.garay.arcade"

  // The bar sizes each slot from its widget's implicit size, so a root that
  // reports nothing collapses to zero width and renders as a gap.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property var games: []
  property var continueRows: []
  property var libraryRows: []
  property string loadError: ""
  property bool scanning: false
  property bool playing: false
  property double nowSeconds: 0

  property string query: ""
  property bool cursorActive: false
  property int cursorIndex: 0

  readonly property int maxLibraryRows: Math.max(10, root.setting("maxLibraryRows", 40))
  readonly property int refreshIntervalSec: Math.max(30, root.setting("refreshIntervalSec", 300))

  // One flat list of everything the cursor can land on, Continue first. Built
  // from the same arrays the view renders, so a row can never be reachable by
  // keyboard but missing from the panel, or the reverse.
  readonly property var cursorTargets: {
    var out = []
    for (var i = 0; i < continueRows.length; i++) out.push({ kind: "continue", game: continueRows[i] })
    for (var j = 0; j < libraryRows.length; j++) out.push({ kind: "library", game: libraryRows[j] })
    return out
  }
  readonly property var selectedTarget:
    cursorTargets.length > 0
      ? cursorTargets[Math.max(0, Math.min(cursorIndex, cursorTargets.length - 1))]
      : null

  function targetKey(kind, game) { return kind + ":" + (game ? game.key : "") }
  function selectedKey() { return selectedTarget ? targetKey(selectedTarget.kind, selectedTarget.game) : "" }

  function moveCursor(delta) {
    cursorActive = true
    if (cursorTargets.length === 0) { cursorIndex = 0; return }
    cursorIndex = Math.max(0, Math.min(cursorTargets.length - 1, cursorIndex + delta))
  }

  function refresh() {
    root.nowSeconds = Date.now() / 1000
    root.scanning = true
    scanProcess.running = false
    scanProcess.running = true
  }

  function applyScan(raw) {
    root.scanning = false
    var parsed = Library.parseLibrary(raw)
    root.loadError = parsed.error
    root.games = parsed.games
    root.rebuild()
  }

  function rebuild() {
    root.continueRows = root.query ? [] : Library.resumableGames(root.games, 6)
    root.libraryRows = Library.filterGames(root.games, root.query, root.maxLibraryRows)
    if (root.cursorIndex >= root.cursorTargets.length)
      root.cursorIndex = Math.max(0, root.cursorTargets.length - 1)
  }

  function setQuery(next) {
    root.query = next
    root.cursorIndex = 0
    root.rebuild()
  }

  // `resume` is what Enter means everywhere in this panel; Shift+Enter and the
  // "f" key are the way back to a title screen.
  function launch(game, resume) {
    if (!game) return
    var args = [
      root.pluginDir + "/bin/omarchy-arcade-launch",
      "--core", game.core,
      "--rom", game.rom
    ]
    if (resume && game.resumeSlot) args.push("--slot", game.resumeSlot)
    if (!root.setting("silenceNotifications", true)) args.push("--keep-notifications")
    if (!root.setting("stayAwake", true)) args.push("--allow-idle")
    root.close()
    Quickshell.execDetached(args)
    // The scan that follows the game is what moves it to the top of Continue,
    // so schedule one rather than waiting for the interval to come around.
    playPoll.restart()
  }

  function activateCursor(resume) {
    if (!selectedTarget) return
    root.launch(selectedTarget.game, resume)
  }

  onOpenedChanged: {
    if (opened) {
      root.setQuery("")
      root.cursorActive = false
      root.cursorIndex = 0
      root.refresh()
    }
  }

  Process {
    id: scanProcess
    command: [root.pluginDir + "/bin/omarchy-arcade-scan"]
    environment: ({ "ARCADE_ROM_DIR": String(root.setting("romDir", "") || "") })
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyScan(text)
    }
  }

  // The bar icon lights while a game is running, which is the one piece of
  // state worth showing without opening anything.
  Process {
    id: playProcess
    command: ["pgrep", "-x", "retroarch"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.playing = String(text || "").trim().length > 0
    }
  }

  Timer {
    id: playPoll
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!playProcess.running) playProcess.running = true
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!root.opened) root.refresh()
  }

  // manageIpc is off because this handler adds `refresh` on top of the base
  // open/close/toggle set, so a keybinding can rescan without opening
  // anything: `omarchy-shell io.garay.arcade refresh`.
  IpcHandler {
    target: "io.garay.arcade"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function status(): string {
      return JSON.stringify({
        games: root.games.length,
        resumable: Library.resumableGames(root.games, 999).length,
        playing: root.playing
      })
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰊴"
    active: root.playing
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: search.activeFocus

      onMoveRequested: function (dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: root.activateCursor(true)
      onCloseRequested: {
        if (root.query) root.setQuery("")
        else root.close()
      }
      onTabRequested: Qt.callLater(function () { search.forceActiveFocus() })
      onTextKey: function (text) {
        if (text === "/") Qt.callLater(function () { search.forceActiveFocus() })
        else if (text === "r" || text === "R") root.refresh()
        else if (text === "f" || text === "F") root.activateCursor(false)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: content
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Arcade"
            meta: {
              if (root.scanning && root.games.length === 0) return "Scanning your library…"
              if (root.loadError) return root.loadError
              if (root.games.length === 0) return "No games found"
              var parts = [root.games.length + (root.games.length === 1 ? " game" : " games")]
              var resumable = Library.resumableGames(root.games, 999).length
              if (resumable > 0) parts.push(resumable + " to continue")
              if (root.playing) parts.push("playing now")
              return parts.join(" · ")
            }
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: "󰊴"
                color: root.playing ? root.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
              }
            }
          }

          // --- Error callout ---------------------------------------------
          BorderSurface {
            visible: root.loadError !== ""
            width: parent.width
            implicitHeight: errorText.implicitHeight + Style.space(20)
            color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.10)
            borderSpec: Border.flat(Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: errorText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(10)
              text: root.loadError
              textFormat: Text.PlainText
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          // --- Search ------------------------------------------------------
          TextField {
            id: search
            width: parent.width
            visible: root.games.length > 0
            placeholderText: "Search games"
            text: root.query
            foreground: root.foreground
            font.family: root.fontFamily
            onTextChanged: if (text !== root.query) root.setQuery(text)
            Keys.onDownPressed: { keyCatcher.forceActiveFocus(); root.moveCursor(1) }
            Keys.onEscapePressed: {
              if (root.query) root.setQuery("")
              keyCatcher.forceActiveFocus()
            }
            Keys.onReturnPressed: {
              keyCatcher.forceActiveFocus()
              root.cursorActive = true
              root.activateCursor(true)
            }
          }

          // --- Continue ----------------------------------------------------
          PanelSectionHeader {
            width: parent.width
            visible: root.continueRows.length > 0
            text: "Continue"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            width: parent.width
            visible: root.continueRows.length > 0
            spacing: Style.space(6)

            Repeater {
              model: root.continueRows

              // The Continue row is the widest, tallest thing in the panel on
              // purpose: the save-state thumbnail is the reason to open this
              // at all, and shrinking it to a list icon throws that away.
              delegate: Rectangle {
                id: continueRow
                required property int index
                required property var modelData
                readonly property bool hasCursor:
                  root.cursorActive && root.selectedKey() === root.targetKey("continue", modelData)

                width: parent.width
                height: Style.space(58)
                radius: Style.cornerRadius
                color: hasCursor ? Style.selectedFill : (rowHover.containsMouse ? Style.hoverFill : "transparent")

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(10)

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(66)
                    height: Style.space(44)
                    radius: Style.cornerRadius
                    color: Util.alpha(root.foreground, 0.10)
                    clip: true

                    Image {
                      id: stateThumb
                      anchors.fill: parent
                      source: Util.fileUrl(continueRow.modelData.resumeArt)
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: true
                      // The state thumbnail is rewritten in place every time
                      // you save, so a cached copy would show a stale frame.
                      cache: false
                      visible: status === Image.Ready
                    }

                    // Without a thumbnail the row still has to read as a
                    // resumable game, so the slot itself becomes the badge.
                    Text {
                      anchors.centerIn: parent
                      visible: stateThumb.status !== Image.Ready
                      text: continueRow.modelData.resumeSlot === "auto"
                            ? "AUTO" : ("SLOT " + continueRow.modelData.resumeSlot)
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Style.space(66) - Style.space(10) - resumeHint.width - Style.space(10)
                    spacing: Style.space(2)

                    Text {
                      width: parent.width
                      text: continueRow.modelData.title
                      textFormat: Text.PlainText
                      color: continueRow.hasCursor ? Color.menu.selectedText : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      text: {
                        var g = continueRow.modelData
                        var bits = []
                        var ago = Library.formatAgo(g.resumeAt, root.nowSeconds)
                        if (ago) bits.push("saved " + ago)
                        var sys = Library.systemAndCore(g)
                        if (sys) bits.push(sys)
                        return bits.join(" · ")
                      }
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  Text {
                    id: resumeHint
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰐊"
                    color: continueRow.hasCursor ? root.accent : root.dim
                    opacity: continueRow.hasCursor || rowHover.containsMouse ? 1 : 0.4
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.iconLarge
                  }
                }

                MouseArea {
                  id: rowHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  onContainsMouseChanged: if (containsMouse) {
                    root.cursorActive = true
                    root.cursorIndex = continueRow.index
                  }
                  // Right-click is the mouse's way of saying "from the top",
                  // matching Shift+Enter and "f" on the keyboard.
                  onClicked: function (mouse) {
                    root.launch(continueRow.modelData, mouse.button !== Qt.RightButton)
                  }
                }
              }
            }
          }

          PanelSeparator {
            width: parent.width
            visible: root.continueRows.length > 0 && root.libraryRows.length > 0
            foreground: root.foreground
          }

          // --- Library -------------------------------------------------------
          PanelSectionHeader {
            width: parent.width
            visible: root.libraryRows.length > 0
            text: root.query
                  ? (root.libraryRows.length + " match" + (root.libraryRows.length === 1 ? "" : "es"))
                  : "Library"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            width: parent.width
            visible: root.libraryRows.length > 0
            spacing: Style.space(2)

            Repeater {
              model: root.libraryRows

              delegate: Rectangle {
                id: libraryRow
                required property int index
                required property var modelData
                readonly property bool hasCursor:
                  root.cursorActive && root.selectedKey() === root.targetKey("library", modelData)

                width: parent.width
                height: Style.space(38)
                radius: Style.cornerRadius
                color: hasCursor ? Style.selectedFill : (libHover.containsMouse ? Style.hoverFill : "transparent")

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(8)

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(26)
                    height: Style.space(26)
                    radius: Style.cornerRadius
                    color: Util.alpha(root.foreground, 0.08)
                    clip: true

                    Image {
                      id: boxart
                      anchors.fill: parent
                      source: Util.fileUrl(libraryRow.modelData.art)
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: true
                      visible: status === Image.Ready
                    }

                    Text {
                      anchors.centerIn: parent
                      visible: boxart.status !== Image.Ready
                      text: "󰋙"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.iconSmall
                    }
                  }

                  // The system belongs under the title rather than beside it:
                  // on the right it competed with the title for the same
                  // width and lost, eliding to "Nintendo - Sup...".
                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Style.space(26) - Style.space(8) * 2 - resumeDot.width
                    spacing: Style.space(1)

                    Text {
                      width: parent.width
                      text: libraryRow.modelData.title
                      textFormat: Text.PlainText
                      color: libraryRow.hasCursor ? Color.menu.selectedText : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      visible: text.length > 0
                      text: Library.systemAndCore(libraryRow.modelData)
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  // A dot rather than a third line: it says "this one has a
                  // save" at a glance without growing the row again.
                  Rectangle {
                    id: resumeDot
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(5)
                    height: width
                    radius: width / 2
                    color: root.accent
                    visible: libraryRow.modelData.resumeAt > 0
                  }
                }

                MouseArea {
                  id: libHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  onContainsMouseChanged: if (containsMouse) {
                    root.cursorActive = true
                    root.cursorIndex = root.continueRows.length + libraryRow.index
                  }
                  onClicked: function (mouse) {
                    root.launch(libraryRow.modelData, mouse.button !== Qt.RightButton)
                  }
                }
              }
            }
          }

          // --- Empty state ---------------------------------------------------
          // The first screen most people will see, so it says where to put
          // ROMs rather than only reporting their absence.
          Column {
            width: parent.width
            visible: root.games.length === 0 && !root.scanning && root.loadError === ""
            spacing: Style.space(6)

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "󰊴"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              text: "Drop ROMs into ~/Games/roms, or scan them in RetroArch, then press r."
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Text {
            width: parent.width
            visible: root.query !== "" && root.libraryRows.length === 0 && root.games.length > 0
            horizontalAlignment: Text.AlignHCenter
            text: "No games match “" + root.query + "”"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // --- Footer ---------------------------------------------------------
          Text {
            width: parent.width
            visible: root.games.length > 0
            horizontalAlignment: Text.AlignHCenter
            text: "⏎ resume   f start fresh   / search   r rescan"
            textFormat: Text.PlainText
            color: root.dim
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
