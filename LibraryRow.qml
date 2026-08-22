import QtQuick
import qs.Commons
import qs.Ui
import "ArcadeSession.js" as Session

// One library row. Collapsed it is a list line; under the cursor it grows to
// show what it knows about the game -- playtime, and whether there is a save
// to come back to. Only the focused row pays for the space, so a
// hundred-game library still reads as a list.
Rectangle {
  id: row

  property var game: null
  property bool hasCursor: false
  property string filterText: ""
  property double nowSeconds: 0

  // Tokens.
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal hovered()
  signal activated(bool resume)

  width: parent ? parent.width : 0
  height: hasCursor ? Style.space(62) : Style.space(38)
  radius: Style.cornerRadius
  color: hasCursor ? Style.selectedFill : (area.containsMouse ? Style.hoverFill : "transparent")
  Behavior on color { ColorAnimation { duration: 90 } }
  clip: true

  Behavior on height {
    NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
  }

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
    anchors.topMargin: Style.space(6)
    anchors.bottomMargin: Style.space(6)
    spacing: Style.space(8)

    Rectangle {
      anchors.top: parent.top
      width: row.hasCursor ? Style.space(48) : Style.space(26)
      height: width
      radius: Style.cornerRadius
      color: Util.alpha(row.foreground, 0.08)
      clip: true
      border.width: 1
      border.color: row.hasCursor
                    ? Util.alpha(row.accent, 0.55)
                    : Util.alpha(row.foreground, 0.14)
      Behavior on border.color { ColorAnimation { duration: 90 } }

      Behavior on width {
        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
      }

      Image {
        id: boxart
        anchors.fill: parent
        source: row.game ? Util.fileUrl(row.game.art) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: status === Image.Ready
      }

      Text {
        anchors.centerIn: parent
        visible: boxart.status !== Image.Ready
        text: "󰋙"
        color: row.dim
        font.family: row.fontFamily
        font.pixelSize: Style.font.iconSmall
      }
    }

    // The system belongs under the title rather than beside it: on the right
    // it competed with the title for the same width and lost, eliding to
    // "Nintendo - Sup...".
    Column {
      anchors.top: parent.top
      width: parent.width - (row.hasCursor ? Style.space(48) : Style.space(26))
             - Style.space(8) * 2 - resumeDot.width
      spacing: Style.space(1)

      Text {
        width: parent.width
        // Rich text so the search match lights up inside the title; with no
        // query this is plain escaped text, rendering as before.
        text: row.game ? Session.highlightTitle(row.game.title, row.filterText, String(row.accent)) : ""
        textFormat: Text.StyledText
        color: row.hasCursor ? Color.menu.selectedText : row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: text.length > 0
        text: row.game ? Session.systemAndCore(row.game) : ""
        textFormat: Text.PlainText
        color: row.dim
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: row.hasCursor
        opacity: row.hasCursor ? 1 : 0
        text: row.game ? Session.playSummary(row.game, row.nowSeconds) : ""
        textFormat: Text.PlainText
        color: row.dim
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        Behavior on opacity { NumberAnimation { duration: 90 } }
      }

      // Only says something when there is something to say: a save to come
      // back to, and which slot it is in.
      Text {
        width: parent.width
        visible: row.hasCursor && row.game && row.game.resumeAt > 0
        text: {
          if (!row.game) return ""
          var slot = row.game.resumeSlot === "auto" ? "auto save" : ("slot " + row.game.resumeSlot)
          var ago = Session.formatAgo(row.game.resumeAt, row.nowSeconds)
          return "⏎ resumes " + slot + (ago ? " · saved " + ago : "")
        }
        textFormat: Text.PlainText
        color: row.accent
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    // A dot rather than a third line: it says "this one has a save" at a
    // glance without growing the row again.
    Rectangle {
      id: resumeDot
      anchors.top: parent.top
      anchors.topMargin: Style.space(6)
      width: Style.space(5)
      height: width
      radius: width / 2
      color: row.accent
      visible: row.game !== null && row.game.resumeAt > 0
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onContainsMouseChanged: if (containsMouse) row.hovered()
    onClicked: function (mouse) {
      row.hovered()
      row.activated(mouse.button !== Qt.RightButton)
    }
  }
}
