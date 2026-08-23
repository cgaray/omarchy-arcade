import QtQuick
import qs.Commons
import qs.Ui
import "ArcadeSession.js" as Session

// The reading surface under the grid: what is selected, what it runs, and
// whether there is a save waiting. Fades itself in on every game change so
// keyboard browsing settles rather than swaps.
Rectangle {
  id: card

  property var game: null
  property double nowSeconds: 0

  // Tokens.
  property color foreground: Color.menu.text
  property color accent: Color.accent
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily
  property int cornerRadius: Style.cornerRadius

  radius: card.cornerRadius
  color: card.selectedBackground
  border.width: Math.max(1, Style.space(1))
  border.color: card.accent

  onGameChanged: if (game) fade.restart()

  SequentialAnimation {
    id: fade
    NumberAnimation {
      target: card
      property: "opacity"
      from: 0.55; to: 1
      duration: 160
      easing.type: Easing.OutCubic
    }
  }

  Row {
    anchors.fill: parent
    anchors.margins: Style.space(12)
    spacing: Style.space(16)

    Rectangle {
      width: Style.space(142)
      height: parent.height
      radius: card.cornerRadius
      color: Util.alpha(card.foreground, 0.08)
      clip: true

      Image {
        id: art
        anchors.fill: parent
        // Prefer the paused frame when there is one.
        source: {
          if (!card.game) return ""
          if (card.game.resumeArt) return Util.fileUrl(card.game.resumeArt)
          return Util.fileUrl(card.game.art)
        }
        sourceSize.width: Style.space(320)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: !(card.game && card.game.resumeArt)
        visible: status === Image.Ready
      }

      Text {
        anchors.centerIn: parent
        visible: art.status !== Image.Ready
        text: "󰊴"
        color: card.foreground
        opacity: 0.28
        font.family: card.fontFamily
        font.pixelSize: Style.font.displayLarge
      }
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - Style.space(158)
      spacing: Style.space(5)

      Text {
        width: parent.width
        text: card.game ? card.game.title : ""
        textFormat: Text.PlainText
        color: card.selectedText
        font.family: card.fontFamily
        font.pixelSize: Style.font.title
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: card.game ? Session.systemAndCore(card.game) : ""
        textFormat: Text.PlainText
        color: card.foreground
        font.family: card.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: {
          if (!card.game) return ""
          var bits = []
          var summary = Session.playSummary(card.game, card.nowSeconds)
          if (summary) bits.push(summary)
          if (card.game.resumeAt > 0) bits.push("Enter resumes")
          return bits.join(" · ")
        }
        textFormat: Text.PlainText
        color: card.accent
        font.family: card.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }
  }
}
