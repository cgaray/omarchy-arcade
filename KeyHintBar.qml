import QtQuick
import qs.Commons
import qs.Ui

// Contextual keyboard hints: a row of keycap-plus-label chips describing the
// actions available right now. Pure presentation -- the caller owns which
// hints fit the current mode and passes them in, so this file holds no state
// worth testing.
Flow {
  id: root

  property var hints: []
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property int fontSize: Style.font.caption

  spacing: Style.space(12)
  topPadding: Style.space(2)
  bottomPadding: Style.space(2)

  Repeater {
    model: root.hints

    Row {
      id: chip
      required property var modelData
      spacing: Style.space(5)

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: capText.implicitWidth + Style.space(9)
        height: capText.implicitHeight + Style.space(6)
        radius: height / 2
        color: Util.alpha(root.foreground, 0.08)
        border.width: 1
        border.color: Util.alpha(root.foreground, 0.20)

        Text {
          id: capText
          anchors.centerIn: parent
          text: chip.modelData.key
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: root.fontSize
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.modelData.label
        textFormat: Text.PlainText
        color: Util.alpha(root.foreground, 0.72)
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
      }
    }
  }
}
