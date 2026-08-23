import QtQuick
import qs.Commons
import qs.Ui
import "ArcadeSession.js" as Session

// One cover-art tile in the overlay grid. Pure presentation plus two
// signals: the grid owns which index is selected and what launching means.
Item {
  id: tile

  property var game: null
  property bool hasCursor: false
  property string filterText: ""

  // Tokens, handed in so the tile never reaches outside itself.
  property color foreground: Color.menu.text
  property color dim: Util.alpha(foreground, 0.62)
  property color accent: Color.accent
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color background: Color.menu.background
  property string fontFamily: Style.font.menuFamily
  property int cornerRadius: Style.cornerRadius
  property int artHeight: Style.space(186)

  signal hovered()
  signal activated(bool resume)

  readonly property bool hot: hasCursor || tileHover.containsMouse

  width: Style.space(292)
  height: Style.space(270)
  z: hot ? 2 : 1

  Rectangle {
    id: frame
    anchors.fill: parent
    anchors.margins: Style.space(6)
    radius: tile.cornerRadius
    color: tile.hasCursor ? tile.selectedBackground
                          : (tileHover.containsMouse ? Style.hoverFill : "transparent")
    border.width: tile.hasCursor ? 1 : 0
    border.color: Util.alpha(tile.accent, 0.55)

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Style.space(3)
      radius: tile.cornerRadius
      color: tile.accent
      visible: tile.hasCursor
    }

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(8)
      spacing: Style.space(6)

      Rectangle {
        width: parent.width
        height: tile.artHeight
        radius: tile.cornerRadius
        color: Util.alpha(tile.foreground, 0.08)
        clip: true

        Image {
          id: cover
          anchors.fill: parent
          anchors.margins: Style.space(2)
          // A saved game shows the frame you paused on rather than its box
          // art -- the same promise the Continue shelf makes in the panel.
          source: {
            if (!tile.game) return ""
            if (tile.game.resumeArt) return Util.fileUrl(tile.game.resumeArt)
            return Util.fileUrl(tile.game.art)
          }
          // Cover art and snapshots both arrive far larger than the tile
          // shows; bounding the decode keeps a wall of tiles from holding
          // hundreds of full-resolution textures.
          sourceSize.width: Style.space(640)
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          // Snapshots are rewritten in place on every save, so a cached copy
          // would go stale; box art never changes.
          cache: !(tile.game && tile.game.resumeArt)
          visible: status === Image.Ready
        }

        // Most libraries have art for some games and not others, so the
        // fallback has to be a design rather than a hole.
        Text {
          anchors.centerIn: parent
          visible: cover.status !== Image.Ready
          text: "󰊴"
          color: tile.foreground
          opacity: 0.28
          font.family: tile.fontFamily
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
          color: tile.accent

          Text {
            id: resumeBadge
            anchors.centerIn: parent
            text: "RESUME"
            color: tile.background
            font.family: tile.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }

      Text {
        width: parent.width
        // Rich text so the search match can light up inside the title; the
        // empty-query path returns plain escaped text, which renders the
        // same as before.
        text: tile.game ? Session.highlightTitle(tile.game.title, tile.filterText, String(tile.accent)) : ""
        textFormat: Text.StyledText
        color: tile.hasCursor ? tile.selectedText : tile.foreground
        font.family: tile.fontFamily
        font.pixelSize: Style.font.body
        font.weight: tile.hasCursor ? Font.DemiBold : Font.Normal
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: tile.game ? Session.systemAndCore(tile.game) : ""
        textFormat: Text.PlainText
        color: tile.dim
        font.family: tile.fontFamily
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
      onContainsMouseChanged: if (containsMouse) tile.hovered()
      onClicked: function (mouse) {
        tile.hovered()
        tile.activated(mouse.button !== Qt.RightButton)
      }
    }
  }
}
