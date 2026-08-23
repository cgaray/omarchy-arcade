import QtQuick
import qs.Commons
import qs.Ui

// Modal shortcut legend for the desktop wall. Keyboard ownership remains in
// Overlay.qml; this is deliberately presentation-only.
BorderSurface {
  id: root

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color dim: Util.alpha(foreground, 0.62)
  property string fontFamily: Style.font.menuFamily
  property int cornerRadius: Style.cornerRadius

  height: content.implicitHeight + Style.space(24)
  color: background
  radius: cornerRadius

  Column {
    id: content
    anchors.fill: parent
    anchors.margins: Style.space(12)
    spacing: Style.space(6)

    Text {
      text: "Keyboard shortcuts"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      width: parent.width
      text: "↑↓←→ move (PageUp/PageDown by row)    Enter resume    Shift+Enter / right-click start over    type search\nCtrl+S saved states    Tab / Shift+Tab systems    Ctrl+0 all, Ctrl+1..9 jump system    F5 refresh    Ctrl+Backspace clear    Esc back"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}
