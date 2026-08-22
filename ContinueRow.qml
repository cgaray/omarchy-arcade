import QtQuick
import qs.Commons
import qs.Ui
import "ArcadeSession.js" as Session

// One row of the Continue shelf: the frame you paused on, the game, and when
// you saved it. The panel owns cursor bookkeeping and launching.
Rectangle {
  id: row

  property var game: null
  property bool hasCursor: false
  property double nowSeconds: 0

  // Tokens.
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal hovered()
  signal activated(bool resume)

  width: parent ? parent.width : 0
  height: Style.space(58)
  radius: Style.cornerRadius
  color: hasCursor ? Style.selectedFill : (area.containsMouse ? Style.hoverFill : "transparent")
  Behavior on color { ColorAnimation { duration: 90 } }

  // A sliver of accent marks the row the keyboard is on, so the cursor reads
  // at a glance even while scanning down the shelf.
  Rectangle {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(2)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(3)
    height: parent.height - Style.space(14)
    radius: width / 2
    color: row.accent
    opacity: row.hasCursor ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 90 } }
  }

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
      color: Util.alpha(row.foreground, 0.10)
      clip: true
      border.width: 1
      border.color: row.hasCursor
                    ? Util.alpha(row.accent, 0.55)
                    : Util.alpha(row.foreground, 0.14)
      Behavior on border.color { ColorAnimation { duration: 90 } }

      Image {
        id: stateThumb
        anchors.fill: parent
        source: row.game ? Util.fileUrl(row.game.resumeArt) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // The state thumbnail is rewritten in place every time you save, so
        // a cached copy would show a stale frame.
        cache: false
        visible: status === Image.Ready
      }

      // Without a thumbnail the row still has to read as a resumable game,
      // so the slot itself becomes the badge.
      Text {
        anchors.centerIn: parent
        visible: stateThumb.status !== Image.Ready
        text: row.game && row.game.resumeSlot === "auto"
              ? "AUTO" : ("SLOT " + (row.game ? row.game.resumeSlot : ""))
        color: row.dim
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - Style.space(66) - Style.space(10) - resumeHint.width - Style.space(10)
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: row.game ? row.game.title : ""
        textFormat: Text.PlainText
        color: row.hasCursor ? Color.menu.selectedText : row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: {
          if (!row.game) return ""
          var bits = []
          var ago = Session.formatAgo(row.game.resumeAt, row.nowSeconds)
          if (ago) bits.push("saved " + ago)
          var sys = Session.systemAndCore(row.game)
          if (sys) bits.push(sys)
          return bits.join(" · ")
        }
        textFormat: Text.PlainText
        color: row.dim
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Text {
      id: resumeHint
      anchors.verticalCenter: parent.verticalCenter
      text: "󰐊"
      color: row.hasCursor ? row.accent : row.dim
      opacity: row.hasCursor || area.containsMouse ? 1 : 0.4
      font.family: row.fontFamily
      font.pixelSize: Style.font.iconLarge
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onContainsMouseChanged: if (containsMouse) row.hovered()
    // Right-click is the mouse's way of saying "from the top", matching
    // Shift+Enter and "f" on the keyboard.
    onClicked: function (mouse) {
      row.hovered()
      row.activated(mouse.button !== Qt.RightButton)
    }
  }
}
