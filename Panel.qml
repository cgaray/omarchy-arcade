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

  // Commands are spawned by absolute path. execDetached does not go through a
  // shell and does not inherit a login PATH, so a bare "omarchy-shell" here
  // silently spawned nothing -- which is exactly how the "b" shortcut and the
  // install button came to do nothing at all. Every first-party plugin that
  // spawns an Omarchy command resolves it through OMARCHY_PATH; so do we.
  readonly property string omarchyBin: Quickshell.env("OMARCHY_PATH") + "/bin"


  // The bar sizes each slot from its widget's implicit size, so a root that
  // reports nothing collapses to zero width and renders as a gap.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property var games: []
  property var extensions: []
  property var scanMeta: ({})
  readonly property bool retroarchMissing: scanMeta.retroarchInstalled === false
  property var continueRows: []
  property var libraryRows: []
  property string loadError: ""
  property bool scanning: false
  property bool playing: false
  property double nowSeconds: 0

  property string query: ""
  property string systemFilter: ""
  readonly property var systems: Library.systemsOf(root.games)
  // A Dropdown popup takes the keyboard while it is open; the panel's own
  // cursor keys would otherwise move the selection behind it.
  property bool dropdownOpen: false
  property bool cursorActive: false
  property int cursorIndex: 0

  // Tab walks the panel's three landing places in the order they are drawn:
  // the search box, the system row, then the games. Zones that are not on
  // screen -- no search box before anything is scanned, no system row in a
  // single-system library -- drop out of the cycle rather than becoming a
  // Tab press that appears to do nothing.
  property string focusZone: "list"
  property int systemCursor: 0

  readonly property var focusZones: {
    var out = []
    if (search.visible) out.push("search")
    if (systemStrip.visible) out.push("systems")
    out.push("list")
    return out
  }

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

  // A Column inside a Flickable does no scrolling of its own, so walking the
  // cursor past the fold used to move a selection nobody could see. Ask the
  // row where it ended up and bring it back into view.
  function ensureVisible(item) {
    if (!item || !panelFlick) return
    Qt.callLater(function () {
      var top = item.mapToItem(panelFlick.contentItem, 0, 0).y
      var bottom = top + item.height
      var margin = Style.space(10)
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < panelFlick.contentY + margin)
        panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > panelFlick.contentY + panelFlick.height - margin)
        panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

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
    root.lastFingerprint = ""
    var parsed = Library.parseLibrary(raw)
    root.loadError = parsed.error
    root.games = parsed.games
    root.extensions = parsed.extensions
    root.scanMeta = parsed.meta
    root.rebuild()
  }

  function rebuild() {
    // A text search means the user is hunting one title, so the shelf steps
    // out of the way. A system filter is a place to be, so the shelf follows
    // them into it rather than vanishing.
    root.continueRows = root.query ? [] : Library.resumableIn(root.games, root.systemFilter, 6)
    // A filter that survives a rescan but names a system no longer present
    // would silently show an empty library, so drop it.
    if (root.systemFilter) {
      var stillThere = false
      for (var s = 0; s < root.systems.length; s++)
        if (root.systems[s].system === root.systemFilter) stillThere = true
      if (!stillThere) root.systemFilter = ""
    }
    root.libraryRows = Library.filterGames(root.games, root.query, root.maxLibraryRows, root.systemFilter)
    if (root.cursorIndex >= root.cursorTargets.length)
      root.cursorIndex = Math.max(0, root.cursorTargets.length - 1)
  }

  function setQuery(next) {
    root.query = next
    root.cursorIndex = 0
    root.rebuild()
  }

  function enterZone(zone) {
    root.focusZone = zone
    if (zone === "search") {
      Qt.callLater(function () { search.forceActiveFocus() })
      return
    }
    if (zone === "systems") {
      // Land on whichever chip is currently in force, so Tab into the row
      // does not silently move the selection.
      root.systemCursor = root.systemIndexOf(root.systemFilter)
    }
    if (zone === "list") root.cursorActive = true
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function cycleZone(delta) {
    var zones = root.focusZones
    var at = zones.indexOf(root.focusZone)
    if (at < 0) at = zones.length - 1
    root.enterZone(zones[(at + delta + zones.length) % zones.length])
  }

  // Index into the chip row, All being 0.
  function systemIndexOf(system) {
    if (!system) return 0
    for (var i = 0; i < root.systems.length; i++)
      if (root.systems[i].system === system) return i + 1
    return 0
  }

  function systemAt(index) {
    if (index <= 0) return ""
    return root.systems[index - 1] ? root.systems[index - 1].system : ""
  }

  // Moving along the chip row applies as it goes, so the list below is always
  // showing what the highlighted chip means.
  function moveSystemCursor(delta) {
    var count = root.systems.length + 1
    if (count <= 1) return
    root.systemCursor = Math.max(0, Math.min(count - 1, root.systemCursor + delta))
    root.setSystem(root.systemAt(root.systemCursor))
  }

  function setSystem(system) {
    root.systemFilter = system
    root.cursorIndex = 0
    root.systemCursor = root.systemIndexOf(system)
    root.rebuild()
    Qt.callLater(function () { panelFlick.contentY = 0 })
  }

  // "s" walks the filter row, All included, so the whole library stays
  // reachable from the keyboard without hunting for the chip.
  function cycleSystem(delta) {
    var count = root.systems.length + 1
    if (count <= 1) return
    var at = root.systemIndexOf(root.systemFilter)
    root.setSystem(root.systemAt((at + delta + count) % count))
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
      root.focusZone = "list"
      root.systemCursor = root.systemIndexOf(root.systemFilter)
      root.refresh()
    }
  }

  // Recording a core choice is a write, so it goes through the same helper the
  // CLI uses rather than the panel editing cores.conf itself. Empty coreId
  // means "forget my choice and go back to the default".
  function chooseCore(ext, coreId) {
    if (!ext) return
    coreSetProcess.running = false
    coreSetProcess.command = coreId
      ? [root.pluginDir + "/bin/omarchy-arcade-cores", "set", ext, coreId]
      : [root.pluginDir + "/bin/omarchy-arcade-cores", "unset", ext]
    coreSetProcess.running = true
  }

  Process {
    id: coreSetProcess
    // The choice changes which core the scanner resolves, so the library has
    // to be rebuilt before the rows can be believed again.
    onExited: root.refresh()
  }

  // The overlay is a separate entry point in the same plugin, so it is
  // summoned by id through the shell rather than reached in QML.
  function browseAll() {
    root.close()
    Quickshell.execDetached([
      root.omarchyBin + "/omarchy-shell", "-q", "shell", "summon", root.pluginId,
      JSON.stringify({ system: root.systemFilter })
    ])
  }

  function installRetroArch() {
    root.close()
    Quickshell.execDetached([
      root.omarchyBin + "/omarchy-launch-floating-terminal-with-presentation",
      "omarchy-install-gaming-retroarch"
    ])
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


  // --- Watching for new ROMs --------------------------------------------------
  // A full scan costs a second or two on a large library, which is far too
  // much to run on a short timer. The scanner's --fingerprint mode costs
  // milliseconds, so poll that and only pay for a rescan when it moves.
  // Catches ROMs added or removed, new save states, playlist imports, and
  // core choices made elsewhere.
  property string lastFingerprint: ""

  Process {
    id: watchProcess
    command: [root.pluginDir + "/bin/omarchy-arcade-scan", "--fingerprint"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = String(text || "").trim()
        if (!next.length) return
        // The first reading establishes a baseline rather than counting as a
        // change, so opening the panel does not immediately rescan twice.
        if (root.lastFingerprint === "") { root.lastFingerprint = next; return }
        if (next === root.lastFingerprint) return
        root.lastFingerprint = next
        root.refresh()
      }
    }
  }

  Timer {
    // Runs whether or not the panel is open, so the bar count and the "to
    // continue" tally are already right when it is opened.
    interval: Math.max(2, root.setting("watchIntervalSec", 10)) * 1000
    running: root.setting("watchRoms", true)
    repeat: true
    onTriggered: if (!watchProcess.running && !root.scanning) watchProcess.running = true
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
    function browse(): void { root.browseAll() }
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
      // Right-click hands the current system over to the fullscreen grid, so
      // the two surfaces read as one product rather than two plugins that
      // happen to share a scanner.
      if (buttonCode === Qt.RightButton) root.browseAll()
      else if (buttonCode === Qt.MiddleButton) root.refresh()
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
      blocked: search.activeFocus || root.dropdownOpen

      onMoveRequested: function (dx, dy) {
        if (root.focusZone === "systems") {
          if (dx !== 0) root.moveSystemCursor(dx)
          // Down out of the chip row is the natural way into the games.
          else if (dy > 0) root.enterZone("list")
          else if (dy < 0 && search.visible) root.enterZone("search")
          return
        }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: {
        // The chip already applied as the cursor passed over it, so Enter
        // means "done choosing" rather than "choose".
        if (root.focusZone === "systems") root.enterZone("list")
        else root.activateCursor(true)
      }
      onCloseRequested: {
        if (root.query) root.setQuery("")
        else if (root.systemFilter) root.setSystem("")
        else root.close()
      }
      onTabRequested: function (direction) { root.cycleZone(direction) }
      onTextKey: function (text) {
        if (text === "/") root.enterZone("search")
        else if (text === "r" || text === "R") root.refresh()
        else if (text === "f" || text === "F") root.activateCursor(false)
        else if (text === "b" || text === "B") root.browseAll()
        else if (text === "s") root.cycleSystem(1)
        else if (text === "S") root.cycleSystem(-1)
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
              if (root.retroarchMissing) return "RetroArch is not installed"
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
            visible: root.games.length > 0 && !root.retroarchMissing
            placeholderText: "Search games"
            text: root.query
            foreground: root.foreground
            font.family: root.fontFamily
            onTextChanged: if (text !== root.query) root.setQuery(text)
            Keys.onTabPressed: root.cycleZone(1)
            Keys.onBacktabPressed: root.cycleZone(-1)
            Keys.onDownPressed: {
              root.enterZone(root.focusZones.length > 1 && systemStrip.visible ? "systems" : "list")
            }
            Keys.onEscapePressed: {
              if (root.query) root.setQuery("")
              keyCatcher.forceActiveFocus()
            }
            Keys.onReturnPressed: {
              root.enterZone("list")
              root.activateCursor(true)
            }
          }

          // --- Systems -------------------------------------------------------
          // Only worth showing once there is more than one system to move
          // between; a single-system library is already filtered.
          Flickable {
            id: systemStrip
            width: parent.width
            visible: root.systems.length > 1 && !root.retroarchMissing
            height: visible ? systemRow.implicitHeight : 0
            contentWidth: systemRow.implicitWidth
            contentHeight: height
            clip: true
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds

            Row {
              id: systemRow
              spacing: Style.space(6)

              Button {
                text: "All · " + root.games.length
                selected: root.systemFilter === ""
                hasCursor: root.focusZone === "systems" && root.systemCursor === 0
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onClicked: { root.focusZone = "systems"; root.setSystem("") }
              }

              Repeater {
                model: root.systems

                Button {
                  required property int index
                  required property var modelData
                  text: modelData.label + " · " + modelData.count
                  selected: root.systemFilter === modelData.system
                  hasCursor: root.focusZone === "systems" && root.systemCursor === index + 1
                  bordered: true
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  onClicked: { root.focusZone = "systems"; root.setSystem(modelData.system) }
                }
              }
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
                  root.cursorActive && root.focusZone === "list"
                  && root.selectedKey() === root.targetKey("continue", modelData)

                width: parent.width
                height: Style.space(58)
                radius: Style.cornerRadius
                color: hasCursor ? Style.selectedFill : (rowHover.containsMouse ? Style.hoverFill : "transparent")

                onHasCursorChanged: if (hasCursor) root.ensureVisible(continueRow)

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
                    root.focusZone = "list"
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
            text: {
              if (root.query)
                return root.libraryRows.length + " match" + (root.libraryRows.length === 1 ? "" : "es")
              if (root.systemFilter) return root.systemFilter
              return "Library"
            }
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
                  root.cursorActive && root.focusZone === "list"
                  && root.selectedKey() === root.targetKey("library", modelData)

                width: parent.width
                // The row grows under the cursor to show what it knows about
                // the game -- playtime, and whether there is a save to come
                // back to. Only the focused row pays for the space, so a
                // hundred-game library still reads as a list.
                height: hasCursor ? Style.space(62) : Style.space(38)
                radius: Style.cornerRadius
                color: hasCursor ? Style.selectedFill : (libHover.containsMouse ? Style.hoverFill : "transparent")
                clip: true

                Behavior on height {
                  NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                }

                onHasCursorChanged: if (hasCursor) root.ensureVisible(libraryRow)

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(10)
                  anchors.topMargin: Style.space(6)
                  anchors.bottomMargin: Style.space(6)
                  spacing: Style.space(8)

                  Rectangle {
                    anchors.top: parent.top
                    width: libraryRow.hasCursor ? Style.space(48) : Style.space(26)
                    height: width
                    radius: Style.cornerRadius
                    color: Util.alpha(root.foreground, 0.08)
                    clip: true

                    Behavior on width {
                      NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                    }

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
                    anchors.top: parent.top
                    width: parent.width - (libraryRow.hasCursor ? Style.space(48) : Style.space(26))
                           - Style.space(8) * 2 - resumeDot.width
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

                    Text {
                      width: parent.width
                      visible: libraryRow.hasCursor
                      opacity: libraryRow.hasCursor ? 1 : 0
                      text: Library.playSummary(libraryRow.modelData, root.nowSeconds)
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      Behavior on opacity { NumberAnimation { duration: 90 } }
                    }

                    // Only says something when there is something to say: a
                    // save to come back to, and which slot it is in.
                    Text {
                      width: parent.width
                      visible: libraryRow.hasCursor && libraryRow.modelData.resumeAt > 0
                      text: {
                        var g = libraryRow.modelData
                        var slot = g.resumeSlot === "auto" ? "auto save" : ("slot " + g.resumeSlot)
                        var ago = Library.formatAgo(g.resumeAt, root.nowSeconds)
                        return "⏎ resumes " + slot + (ago ? " · saved " + ago : "")
                      }
                      textFormat: Text.PlainText
                      color: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  // A dot rather than a third line: it says "this one has a
                  // save" at a glance without growing the row again.
                  Rectangle {
                    id: resumeDot
                    anchors.top: parent.top
                    anchors.topMargin: Style.space(6)
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
                    root.focusZone = "list"
                    root.cursorIndex = root.continueRows.length + libraryRow.index
                  }
                  onClicked: function (mouse) {
                    root.launch(libraryRow.modelData, mouse.button !== Qt.RightButton)
                  }
                }
              }
            }
          }

          // --- RetroArch is not installed ------------------------------------
          // Arcade is a front end for something that may simply not be here
          // yet. Omarchy ships an installer for it, so the honest empty state
          // is a button rather than a sentence telling the user to go and
          // find one.
          Column {
            width: parent.width
            visible: root.retroarchMissing
            spacing: Style.space(8)

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
              text: "Arcade plays your games through RetroArch, which is not installed yet."
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Button {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Install RetroArch"
              iconText: "󰇚"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.installRetroArch()
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              text: "Omarchy's own installer, in a terminal. Press r here when it finishes."
              textFormat: Text.PlainText
              color: root.dim
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // --- Empty state ---------------------------------------------------
          // The first screen most people will see, so it says where to put
          // ROMs rather than only reporting their absence.
          Column {
            width: parent.width
            visible: root.games.length === 0 && !root.scanning && root.loadError === ""
                     && !root.retroarchMissing
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

          // --- Cores -----------------------------------------------------------
          // Several installed cores usually claim the same extension, and
          // RetroArch's own .info files are the only honest source for which.
          // Rather than ship a table of opinions, offer the candidates and
          // record the answer. Extensions only one core can open are not
          // shown -- there is nothing to decide.
          PanelSeparator {
            width: parent.width
            visible: coreRows.model.length > 0
            foreground: root.foreground
          }

          PanelSectionHeader {
            width: parent.width
            visible: coreRows.model.length > 0
            text: {
              var undecided = Library.undecidedExtensions(root.extensions).length
              return undecided > 0 ? ("Cores · " + undecided + " to choose") : "Cores"
            }
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              id: coreRows
              model: Library.choosableExtensions(root.extensions)

              delegate: Item {
                id: coreRow
                required property var modelData

                width: parent.width
                height: coreDropdown.implicitHeight

                Dropdown {
                  id: coreDropdown
                  anchors.left: parent.left
                  anchors.right: parent.right
                  label: "." + coreRow.modelData.ext
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  value: coreRow.modelData.chosen

                  // The first entry reverts to the default so a choice is
                  // never a one-way door, and it names what the default
                  // actually resolves to rather than just saying "Auto".
                  options: {
                    var out = [{
                      value: "",
                      label: "Auto · " + (coreRow.modelData.resolved || "first available")
                    }]
                    var cands = coreRow.modelData.candidates
                    for (var i = 0; i < cands.length; i++) {
                      out.push({ value: cands[i].id, label: cands[i].name || cands[i].id })
                    }
                    return out
                  }

                  onPopupOpenChanged: root.dropdownOpen = popupOpen

                  onChanged: function (value) {
                    if (value === coreRow.modelData.chosen) return
                    root.chooseCore(coreRow.modelData.ext, value)
                  }
                }
              }
            }
          }

          // --- Footer ---------------------------------------------------------
          Text {
            width: parent.width
            visible: root.games.length > 0
            horizontalAlignment: Text.AlignHCenter
            text: root.systems.length > 1
                  ? "⇥ zones   ⏎ resume   f fresh   b browse all   r rescan"
                  : "⏎ resume   f start fresh   b browse all   r rescan"
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
