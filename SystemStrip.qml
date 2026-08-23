import QtQuick
import qs.Commons
import qs.Ui

// The system filter row: All plus one counted chip per system, scrolling
// sideways when the names overflow. Both surfaces render this same strip;
// the panel additionally drives a keyboard cursor through cursorIndex,
// which stays -1 whenever the row does not have focus.
Flickable {
  id: strip

  property var systems: []
  property int gameCount: 0
  property string activeSystem: ""
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property real chipFontSize: Style.font.caption
  property int cursorIndex: -1

  signal systemChosen(string system)

  contentWidth: row.implicitWidth
  contentHeight: row.implicitHeight
  clip: true
  flickableDirection: Flickable.HorizontalFlick
  boundsBehavior: Flickable.StopAtBounds

  Row {
    id: row
    spacing: Style.space(6)

    Button {
      text: "All · " + strip.gameCount
      selected: strip.activeSystem === ""
      hasCursor: strip.cursorIndex === 0
      bordered: true
      foreground: strip.foreground
      accent: strip.accent
      fontFamily: strip.fontFamily
      fontSize: strip.chipFontSize
      onClicked: strip.systemChosen("")
    }

    Repeater {
      model: strip.systems

      Button {
        required property int index
        required property var modelData
        text: modelData.label + " · " + modelData.count
        selected: strip.activeSystem === modelData.system
        hasCursor: strip.cursorIndex === index + 1
        bordered: true
        foreground: strip.foreground
        accent: strip.accent
        fontFamily: strip.fontFamily
        fontSize: strip.chipFontSize
        onClicked: strip.systemChosen(modelData.system)
      }
    }
  }
}
