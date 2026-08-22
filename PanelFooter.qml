import QtQuick
import qs.Commons
import qs.Ui

// The panel's pinned shortcut guide: a hairline and the contextual keycap
// chips, fixed below the scroll area so the keys that work right now are
// always in view.
Column {
  id: footer

  property var hints: []
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  spacing: 0

  PanelSeparator {
    width: parent.width
    foreground: footer.foreground
  }

  Item {
    width: parent.width
    height: hintsRow.implicitHeight + Style.space(6)

    KeyHintBar {
      id: hintsRow
      width: parent.width
      anchors.verticalCenter: parent.verticalCenter
      hints: footer.hints
      foreground: footer.foreground
      fontFamily: footer.fontFamily
    }
  }
}
