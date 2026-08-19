import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Library.js" as Library
import "ArcadeSession.js" as Session

// The browsing half of Arcade. The bar popup is for picking up where you left
// off in a few keystrokes; this is for looking at a hundred games and their
// cover art, which a 400px column cannot do.
//
// It shares nothing with Panel.qml at runtime -- the shell instantiates the
// two entry points as separate object trees -- and does not need to. Both run
// the same scanner and read the same cores.conf and save states, so the disk
// is the shared state, and a core chosen in one is already in force in the
// other.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: (root.manifest && root.manifest.id) || "io.github.cgaray.arcade"
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/" + pluginId

  // Commands are spawned by absolute path. execDetached does not go through a
  // shell and does not inherit a login PATH, so a bare "omarchy-shell" here
  // silently spawned nothing -- which is exactly how the "b" shortcut and the
  // install button came to do nothing at all. Every first-party plugin that
  // spawns an Omarchy command resolves it through OMARCHY_PATH; so do we.
  readonly property string omarchyBin: Quickshell.env("OMARCHY_PATH") + "/bin"


  property bool opened: false
  property string filterText: ""
  property string systemFilter: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property var sessionSettings: ({})

  property var games: []
  property var extensions: []
  property var scanMeta: ({})
  property var visibleGames: []
  property string loadError: ""
  property bool scanning: false
  property double nowSeconds: 0

  readonly property bool retroarchMissing: scanMeta.retroarchInstalled === false
  readonly property var systems: Library.systemsOf(root.games)

  // Shares the [menu] surface tokens, so a theme that styles the Omarchy menu
  // styles this too.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color scrim: Color.menu.scrim
  property color accent: Color.accent
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int tileWidth: Style.space(216)
  readonly property int tileHeight: Style.space(212)
  readonly property int artHeight: Style.space(142)

  // --- lifecycle -------------------------------------------------------------

  function open(payloadJson) {
    var args = {}
    if (payloadJson) {
      try { args = JSON.parse(payloadJson) || {} } catch (e) { args = {} }
    }
    root.opened = true
    root.filterText = ""
    // The bar button can hand over the system you were already looking at.
    root.systemFilter = String(args.system || "")
    if (args.settings) root.sessionSettings = args.settings
    root.selectedIndex = 0
    root.cursorActive = true
    root.refresh()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function close() { root.opened = false }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // --- data ------------------------------------------------------------------

  function refresh() {
    root.nowSeconds = Date.now() / 1000
    root.scanning = true
    scanProcess.running = false
    scanProcess.running = true
  }

  function applyScan(raw) {
    root.scanning = false
    root.lastFingerprint = ""
    var parsed = Session.parseScan(raw)
    root.loadError = parsed.error
    root.games = parsed.games
    root.extensions = parsed.extensions
    root.scanMeta = parsed.meta
    root.rebuild()
  }

  function rebuild() {
    var derived = Session.rebuild(root.games, root.filterText, root.systemFilter, 2000, 0)
    root.systemFilter = derived.systemFilter
    root.visibleGames = derived.libraryRows
    if (root.selectedIndex >= root.visibleGames.length)
      root.selectedIndex = Math.max(0, root.visibleGames.length - 1)
    if (root.selectedIndex < 0) root.selectedIndex = 0
    Qt.callLater(function () {
      if (root.visibleGames.length > 0) grid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
    })
  }

  function setFilter(next) {
    root.filterText = next
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuild()
  }

  function setSystem(system) {
    root.systemFilter = system
    root.selectedIndex = 0
    root.rebuild()
    Qt.callLater(function () { grid.positionViewAtIndex(0, GridView.Beginning) })
  }

  function systemIndex() {
    if (!root.systemFilter) return 0
    for (var i = 0; i < root.systems.length; i++)
      if (root.systems[i].system === root.systemFilter) return i + 1
    return 0
  }

  function cycleSystem(delta) {
    var count = root.systems.length + 1
    if (count <= 1) return
    var at = (systemIndex() + delta + count) % count
    root.setSystem(at === 0 ? "" : root.systems[at - 1].system)
  }

  // --- navigation ------------------------------------------------------------

  function columns() {
    return Math.max(1, Math.floor(grid.width / root.tileWidth))
  }

  function move(deltaX, deltaY) {
    if (root.visibleGames.length === 0) return
    root.cursorActive = true
    var next = root.selectedIndex + deltaX + deltaY * root.columns()
    if (next < 0) next = 0
    if (next >= root.visibleGames.length) next = root.visibleGames.length - 1
    root.selectedIndex = next
    grid.positionViewAtIndex(next, GridView.Contain)
  }

  function movePage(delta) {
    if (root.visibleGames.length === 0) return
    var rows = Math.max(1, Math.floor(grid.height / root.tileHeight))
    root.move(0, delta * rows)
  }

  function launch(game, resume) {
    if (!game) return
    var args = Session.launchRequest(game, root.sessionSettings, resume,
      root.pluginDir + "/bin/omarchy-arcade-launch")
    root.dismiss()
    Quickshell.execDetached(args)
  }

  function activate(resume) {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.visibleGames.length) return
    root.launch(root.visibleGames[root.selectedIndex], resume)
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
    environment: Session.scannerEnvironment(root.sessionSettings)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = String(text || "").trim()
        if (!next.length) return
        // The first reading establishes a baseline rather than counting as a
        // change, so opening the panel does not immediately rescan twice.
        if (root.lastFingerprint === "") { root.lastFingerprint = next; return }
        if (!Session.fingerprintChanged(root.lastFingerprint, next)) return
        root.lastFingerprint = next
        root.refresh()
      }
    }
  }

  Timer {
    // Only while the grid is on screen: a closed overlay has no one to tell.
    interval: Math.max(2, 10) * 1000
    running: root.opened
    repeat: true
    onTriggered: if (!watchProcess.running && !root.scanning) watchProcess.running = true
  }

  Process {
    id: scanProcess
    command: [root.pluginDir + "/bin/omarchy-arcade-scan"]
    environment: Session.scannerEnvironment(root.sessionSettings)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyScan(text)
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-arcade"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      // Browsing wants room. Capped so an ultrawide gets a genuine wall of
      // cover art without the card running edge to edge, and the subtraction
      // keeps a margin on smaller displays where the cap never bites.
      width: Math.min(panel.width - Style.space(140), Style.space(1960))
      height: Math.min(panel.height - Style.space(90), Style.space(1180))
      radius: root.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      // Swallow clicks so the scrim's dismiss does not fire through the card.
      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else if (root.systemFilter) root.setSystem("")
            else root.dismiss()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            root.cycleSystem((event.modifiers & Qt.ShiftModifier) ? -1 : 1)
            event.accepted = true
          } else if (event.key === Qt.Key_F5) {
            root.refresh()
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.move(-1, 0); event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.move(1, 0); event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.move(0, -1); event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.move(0, 1); event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.movePage(-1); event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.movePage(1); event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.selectedIndex = 0; grid.positionViewAtBeginning(); event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectedIndex = Math.max(0, root.visibleGames.length - 1)
            grid.positionViewAtEnd(); event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activate(!(event.modifiers & Qt.ShiftModifier))
            event.accepted = true
          } else if (event.text && event.text.length === 1
                     && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            // Typing filters. There is no separate search box to reach for:
            // the whole surface is the search box.
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.lg

        // --- Header ----------------------------------------------------------
        Item {
          width: parent.width
          height: Style.font.displayLarge + Style.space(10)

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(12)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "󰊴"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Arcade"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
              }

              Text {
                text: {
                  if (root.retroarchMissing) return "RetroArch is not installed"
                  if (root.loadError) return root.loadError
                  if (root.scanning && root.games.length === 0) return "Scanning…"
                  return root.visibleGames.length
                    + (root.visibleGames.length === 1 ? " game" : " games")
                    + (root.systemFilter ? " · " + root.systemFilter : "")
                }
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          // The filter doubles as the search readout, right-aligned so the
          // eye lands on it without a box drawn round nothing.
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width / 2)
            text: root.filterText ? root.filterText : "Type to search"
            color: root.filterText ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
          }
        }

        // --- Systems -----------------------------------------------------------
        Flickable {
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
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onClicked: root.setSystem("")
            }

            Repeater {
              model: root.systems
              Button {
                required property var modelData
                text: modelData.label + " · " + modelData.count
                selected: root.systemFilter === modelData.system
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onClicked: root.setSystem(modelData.system)
              }
            }
          }
        }

        // --- Grid ---------------------------------------------------------------
        Item {
          width: parent.width
          height: parent.height - y - footer.height - Style.spacing.lg

          GridView {
            id: grid
            anchors.fill: parent
            model: root.visibleGames
            clip: true
            cellWidth: root.tileWidth
            cellHeight: root.tileHeight
            reuseItems: true
            boundsBehavior: Flickable.StopAtBounds
            visible: root.visibleGames.length > 0

            delegate: Item {
              id: tile
              required property int index
              required property var modelData
              readonly property var game: modelData || null
              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

              width: root.tileWidth
              height: root.tileHeight

              Rectangle {
                anchors.fill: parent
                anchors.margins: Style.space(6)
                radius: root.cornerRadius
                color: tile.hasCursor ? root.selectedBackground
                                      : (tileHover.containsMouse ? Style.hoverFill : "transparent")
                border.width: tile.hasCursor ? Math.max(1, Style.space(2)) : 0
                border.color: root.accent

                Column {
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  spacing: Style.space(6)

                  Rectangle {
                    width: parent.width
                    height: root.artHeight
                    radius: root.cornerRadius
                    color: Util.alpha(root.foreground, 0.08)
                    clip: true

                    Image {
                      id: cover
                      anchors.fill: parent
                      anchors.margins: Style.space(2)
                      source: tile.game ? Util.fileUrl(tile.game.art) : ""
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      visible: status === Image.Ready
                    }

                    // Most libraries have art for some games and not others,
                    // so the fallback has to be a design rather than a hole.
                    Text {
                      anchors.centerIn: parent
                      visible: cover.status !== Image.Ready
                      text: "󰊴"
                      color: root.foreground
                      opacity: 0.28
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.displayLarge
                    }

                    // A save to come back to, said once and quietly.
                    Rectangle {
                      anchors.top: parent.top
                      anchors.right: parent.right
                      anchors.margins: Style.space(6)
                      visible: tile.game !== null && tile.game.resumeAt > 0
                      width: resumeBadge.implicitWidth + Style.space(10)
                      height: resumeBadge.implicitHeight + Style.space(4)
                      radius: height / 2
                      color: root.accent

                      Text {
                        id: resumeBadge
                        anchors.centerIn: parent
                        text: "RESUME"
                        color: root.background
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }

                  Text {
                    width: parent.width
                    text: tile.game ? tile.game.title : ""
                    textFormat: Text.PlainText
                    color: tile.hasCursor ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    text: tile.game ? Library.systemAndCore(tile.game) : ""
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                MouseArea {
                  id: tileHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  onContainsMouseChanged: if (containsMouse) {
                    root.cursorActive = true
                    root.selectedIndex = tile.index
                  }
                  onClicked: function (mouse) {
                    root.selectedIndex = tile.index
                    root.launch(tile.game, mouse.button !== Qt.RightButton)
                  }
                }
              }
            }
          }

          // --- Empty states -----------------------------------------------------
          Column {
            anchors.centerIn: parent
            width: Math.min(parent.width, Style.space(520))
            spacing: Style.space(10)
             visible: root.visibleGames.length === 0 && !root.scanning

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "󰊴"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge * 2
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              text: {
                if (root.retroarchMissing) return "RetroArch is not installed"
                if (root.loadError) return root.loadError
                if (root.filterText) return "No games match “" + root.filterText + "”"
                return "No games yet"
              }
            }

            Button {
              anchors.horizontalCenter: parent.horizontalCenter
              visible: root.retroarchMissing
              text: "Install RetroArch"
              iconText: "󰇚"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: {
                root.dismiss()
                Quickshell.execDetached([
                  root.omarchyBin + "/omarchy-launch-floating-terminal-with-presentation",
                  "omarchy-install-gaming-retroarch"
                ])
              }
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              visible: !root.filterText && !root.loadError && !root.retroarchMissing
              text: "Drop ROMs into ~/Games/roms, or scan them in RetroArch, then press F5."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Text {
            anchors.centerIn: parent
            visible: root.scanning && root.games.length === 0
            text: "Scanning…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }
        }

        // --- Footer --------------------------------------------------------------
        Text {
          id: footer
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "↑↓←→ move   ⏎ play or resume   ⇧⏎ start fresh   ⇥ system   F5 rescan   esc close"
          color: root.dim
          opacity: 0.8
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
