import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
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

  // Detached commands need absolute paths.
  readonly property string omarchyBin: Quickshell.env("OMARCHY_PATH") + "/bin"


  property bool opened: false
  property string filterText: ""
  property string systemFilter: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool helpOpen: false
  property bool savedOnly: false
  property string sortMode: "name"

  property var games: []
  property var extensions: []
  property var visibleGames: []
  property int totalMatches: 0
  property string loadError: ""
  property double nowSeconds: 0


  readonly property bool retroarchMissing: lib.retroarchMissing

  // The hint bar follows the mode: only the keys that work right now are
  // worth showing.
  readonly property var footerHints: {
    if (helpOpen)
      return [{ key: "?", label: "close help" }, { key: "esc", label: "back" }]
    if (retroarchMissing || (games.length === 0 && !lib.scanning))
      return [{ key: "F5", label: "rescan" }, { key: "esc", label: "back" }]
    if (filterText.length > 0)
      return [
        { key: "⌫", label: "erase" },
        { key: "ctrl+⌫", label: "clear filter" },
        { key: "⏎", label: "resume" },
        { key: "?", label: "shortcuts" }
      ]
    return [
      { key: "←↑↓→", label: "move" },
      { key: "⏎", label: "resume" },
      { key: "⇧⏎", label: "start over" },
      { key: "ctrl+s", label: "saved only" },
      { key: "⇥", label: "next system" },
      { key: "⇧⇥", label: "previous system" },
      { key: "?", label: "shortcuts" }
    ]
  }

  property var systems: []
  readonly property var selectedGame:
    root.visibleGames.length > root.selectedIndex ? root.visibleGames[root.selectedIndex] : null

  // Shares the [menu] surface tokens, so a theme that styles the Omarchy menu
  // styles this too.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color scrim: Color.menu.scrim
  property color accent: Color.accent
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property color dim: Util.alpha(foreground, 0.62)
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int gridColumnCount: card.width >= 1600 ? 7 : (card.width >= 1200 ? 6 : 5)
  readonly property int tileWidth: Math.max(Style.space(190), Math.floor((card.width - contentMargin * 2 - Style.space(8)) / gridColumnCount))
  readonly property int artHeight: Math.round(tileWidth * 0.68)
  readonly property int tileHeight: artHeight + Style.space(84)

  // --- lifecycle -------------------------------------------------------------

  function open(payloadJson) {
    var args = {}
    if (payloadJson) {
      try { args = JSON.parse(payloadJson) || {} } catch (e) { args = {} }
    }
    root.opened = true
    root.filterText = ""
    root.savedOnly = false
    // The bar button can hand over the system you were already looking at.
    root.systemFilter = String(args.system || "")
    root.selectedIndex = 0
    root.cursorActive = true
    root.helpOpen = false
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
    lib.refresh()
  }

  function rebuild() {
    var derived = Session.rebuild(root.games, root.filterText, root.systemFilter, 2000, 0, root.savedOnly, root.sortMode)
    root.systemFilter = derived.systemFilter
    root.visibleGames = derived.libraryRows
    root.totalMatches = derived.totalMatches
    root.systems = derived.systems
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

  function setSavedOnly(next) {
    root.savedOnly = next
    root.selectedIndex = 0
    root.rebuild()
  }

  function setSort(mode) {
    root.sortMode = mode
    root.selectedIndex = 0
    root.rebuild()
    Qt.callLater(function () { grid.positionViewAtBeginning() })
  }

  function setSystem(system) {
    root.systemFilter = system
    root.selectedIndex = 0
    root.rebuild()
    Qt.callLater(function () { grid.positionViewAtIndex(0, GridView.Beginning) })
  }

  function cycleSystem(delta) {
    var next = Session.nextSystem(root.systems, root.systemFilter, delta)
    if (next !== root.systemFilter) root.setSystem(next)
  }

  function jumpSystem(slot) {
    var system = Session.systemAtSlot(root.systems, slot)
    if (system !== null && system !== root.systemFilter) root.setSystem(system)
  }

  function systemShortcut(event) {
    if (!(event.modifiers & (Qt.AltModifier | Qt.ControlModifier))) return -1
    if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9)
      return event.key === Qt.Key_0 ? 0 : event.key - Qt.Key_0
    var text = String(event.text || "")
    return /^[0-9]$/.test(text) ? Number(text) : -1
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
    var args = Session.launchRequest(game, resume,
      root.pluginDir + "/bin/omarchy-arcade-launch")
    root.dismiss()
    Quickshell.execDetached(args)
  }

  // Picking a state from the inspector is its own resume gesture: it names
  // the slot outright, newest or not.
  function launchSlot(game, slot) {
    if (!game || !slot) return
    var args = Session.launchRequest(game, true,
      root.pluginDir + "/bin/omarchy-arcade-launch", slot)
    root.dismiss()
    Quickshell.execDetached(args)
  }

  function activate(resume) {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.visibleGames.length) return
    root.launch(root.visibleGames[root.selectedIndex], resume)
  }


  // The library feed, shared with the panel. This surface owns the policy:
  // poll only while the grid is on screen, since a closed overlay has no one
  // to tell.
  ArcadeLibrary {
    id: lib
    pluginDir: root.pluginDir
    watchActive: root.opened
    watchIntervalSec: 10
    onChanged: {
      root.games = lib.games
      root.extensions = lib.extensions
      root.loadError = lib.loadError
      root.rebuild()
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
          // Foreground layers get first refusal, matching Omarchy's menu and
          // confirmation dialogs. Nothing should move behind the help card.
          if (root.helpOpen) {
            if (event.key === Qt.Key_Escape || event.text === "?")
              root.helpOpen = false
            event.accepted = true
            return
          }

          var systemSlot = root.systemShortcut(event)
          if (systemSlot >= 0) {
            root.jumpSystem(systemSlot)
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else if (root.systemFilter) root.setSystem("")
            else if (root.savedOnly) root.setSavedOnly(false)
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            // With Shift held, Qt reports Backtab rather than Tab+Shift.
            root.cycleSystem((event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)) ? -1 : 1)
            event.accepted = true
          } else if (event.key === Qt.Key_F5) {
            root.refresh()
            event.accepted = true
          } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R) {
            root.refresh()
            event.accepted = true
          } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Backspace) {
            root.setFilter("")
            event.accepted = true
          } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_S) {
            root.setSavedOnly(!root.savedOnly)
            event.accepted = true
          } else if (event.text === "?") {
            root.helpOpen = !root.helpOpen
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
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
          } else if (!event.modifiers && event.text && event.text.length === 1
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
              color: root.accent
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
                font.pixelSize: Style.font.title
              }

              Text {
                text: {
                  if (lib.retroarchMissing) return "RetroArch is not installed"
                  if (lib.loadError) return lib.loadError
                  if (lib.scanning && root.games.length === 0) return "Scanning…"
                  if (lib.scanning) return "Refreshing library…"
                  var shown = root.visibleGames.length
                  var base = shown === root.totalMatches
                    ? shown + (shown === 1 ? " game" : " games")
                    : "first " + shown + " of " + root.totalMatches + " games"
                  return base
                    + (root.systemFilter ? " · " + root.systemFilter : "")
                    + (root.savedOnly ? " · saves" : "")
                }
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

          }

          Rectangle {
            id: scanTrack
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Style.space(2)
            visible: lib.scanning
            color: Util.alpha(root.accent, 0.18)
            clip: true

            Rectangle {
              id: scanProgress
              width: Math.max(Style.space(80), scanTrack.width * 0.24)
              height: parent.height
              color: root.accent

              NumberAnimation on x {
                from: -scanProgress.width
                to: scanTrack.width
                duration: 900
                loops: Animation.Infinite
                running: lib.scanning
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
            font.pixelSize: Style.font.title
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
          }
        }

        // --- Systems -----------------------------------------------------------
        SystemStrip {
          width: parent.width
          visible: root.systems.length > 1 && !lib.retroarchMissing
          systems: root.systems
          gameCount: root.games.length
          activeSystem: root.systemFilter
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          chipFontSize: Style.font.bodySmall
          onSystemChosen: function (system) { root.setSystem(system) }
        }

        Item {
          width: parent.width
          height: Style.space(32)

          SortPicker {
            id: sortPicker
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            selectedMode: root.sortMode
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onChosen: function (mode) { root.setSort(mode) }
          }
        }

        // The selected tile has a persistent reading surface, so keyboard
        // browsing never requires opening a game just to inspect its details.
        // A game with several save states grows the card to fit its slot
        // chips; most games keep the compact height.
        Item {
          id: inspector
          width: parent.width
          height: {
            if (!root.selectedGame) return 0
            var slots = root.selectedGame.slots
            return slots && slots.length > 1 ? Style.space(150) : Style.space(116)
          }
          visible: root.selectedGame !== null
          clip: true

          InspectorCard {
            anchors.fill: parent
            game: root.selectedGame
            nowSeconds: root.nowSeconds
            foreground: root.foreground
            accent: root.accent
            selectedBackground: root.selectedBackground
            selectedText: root.selectedText
            fontFamily: root.fontFamily
            cornerRadius: root.cornerRadius
            onResumeSlotChosen: function (slot) { root.launchSlot(root.selectedGame, slot) }
          }
        }

        // --- Grid ---------------------------------------------------------------
        Item {
          width: parent.width
          height: parent.height - y - footer.height - Style.spacing.lg

          GridView {
            id: grid
            anchors.fill: parent
            anchors.rightMargin: Style.space(8)
            model: root.visibleGames
            clip: true
            cellWidth: root.tileWidth
            cellHeight: root.tileHeight
            reuseItems: true
            boundsBehavior: Flickable.StopAtBounds
            visible: root.visibleGames.length > 0

            // Filtering reshuffles the wall; a short fade makes that read as
            // the shelf rearranging itself rather than a hard cut.
            populate: Transition {
              NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 170; easing.type: Easing.OutCubic }
            }
            add: Transition {
              NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 170; easing.type: Easing.OutCubic }
            }
            displaced: Transition {
              NumberAnimation { property: "y"; duration: 120; easing.type: Easing.OutCubic }
            }

            // No grouped sections here: Quattro's GridView rejects them
            // (first-party code only sections ListViews). Session still
            // orders browse-mode rows by system, so each wall clusters
            // cleanly under the header count line.

            delegate: GameTile {
              required property int index
              required property var modelData

              width: root.tileWidth
              height: root.tileHeight
              game: modelData || null
              hasCursor: root.cursorActive && index === root.selectedIndex
              filterText: root.filterText
              foreground: root.foreground
              dim: root.dim
              accent: root.accent
              selectedBackground: root.selectedBackground
              selectedText: root.selectedText
              background: root.background
              fontFamily: root.fontFamily
              cornerRadius: root.cornerRadius
              artHeight: root.artHeight

              onHovered: {
                root.cursorActive = true
                root.selectedIndex = index
              }
              onActivated: function (resume) {
                root.launch(modelData, resume)
              }
            }
          }

          ScrollRail {
            anchors {
              top: parent.top
              bottom: parent.bottom
              right: parent.right
            }
            view: grid
            foreground: root.foreground
            accent: root.accent
          }

          // --- Empty states -----------------------------------------------------
          Column {
            anchors.centerIn: parent
            width: Math.min(parent.width, Style.space(520))
            spacing: Style.space(10)
            visible: root.visibleGames.length === 0 && !lib.scanning

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
                if (lib.retroarchMissing) return "RetroArch is not installed"
                if (lib.loadError) return lib.loadError
                if (root.filterText) return "No games match “" + root.filterText + "”"
                return "No games yet"
              }
            }

            Button {
              anchors.horizontalCenter: parent.horizontalCenter
              visible: lib.retroarchMissing
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
              visible: !root.filterText && !lib.loadError && !lib.retroarchMissing
              text: "Drop ROMs into ~/Games/roms, or scan them in RetroArch, then press F5."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Text {
            anchors.centerIn: parent
            visible: lib.scanning && root.games.length === 0
            text: "Scanning…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }
        }

        // --- Footer --------------------------------------------------------------
        Item {
          id: footer
          width: parent.width
          height: footerHintsRow.implicitHeight

          KeyHintBar {
            id: footerHintsRow
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            hints: root.footerHints
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
          }
        }

      }

      ShortcutHelp {
        visible: root.helpOpen
        z: 20
        width: Math.min(parent.width, Style.space(760))
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        background: root.background
        foreground: root.foreground
        dim: root.dim
        borderSpec: root.borderSpec
        fontFamily: root.fontFamily
        cornerRadius: root.cornerRadius
      }
    }
  }
}
