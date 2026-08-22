import QtQuick
import qs.Commons

// Vertical position rail along the wall's right edge.
Rectangle {
  id: root

  // The view whose scroll position this rail mirrors.
  property var view: null
  property color foreground: Color.foreground
  property color accent: Color.accent

  width: visible ? Style.space(4) : 0
  radius: width / 2
  color: Util.alpha(foreground, 0.15)
  visible: view && view.visible && view.contentHeight > view.height + Style.space(1)

  Rectangle {
    width: parent.width
    radius: width / 2
    clip: true
    color: root.accent
    height: Math.max(
      Style.space(48),
      parent.height * Math.min(1, root.view.visibleArea.heightRatio))
    y: (parent.height - height) * Math.min(1, Math.max(0,
      root.view.visibleArea.yPosition
      / Math.max(0.001, 1 - root.view.visibleArea.heightRatio)))

  }
}
