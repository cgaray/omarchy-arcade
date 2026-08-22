import QtQuick
import qs.Commons
import qs.Ui

// Compact desktop ordering control. The overlay owns the selected mode and
// data rebuild; this component only presents the available choices.
Row {
  id: root

  property string selectedMode: "name"
  property color foreground: Color.menu.text
  property color accent: Color.accent
  property string fontFamily: Style.font.menuFamily

  signal chosen(string mode)

  spacing: Style.space(6)

  Text {
    anchors.verticalCenter: parent.verticalCenter
    text: "Sort"
    color: Util.alpha(root.foreground, 0.62)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Repeater {
    model: [
      { mode: "added", label: "Date added" },
      { mode: "save", label: "Save date" },
      { mode: "played", label: "Last played" },
      { mode: "name", label: "Name" }
    ]

    Button {
      required property var modelData
      text: modelData.label
      selected: root.selectedMode === modelData.mode
      bordered: true
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      onClicked: root.chosen(modelData.mode)
    }
  }
}
