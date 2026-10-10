import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "../nasaq.commons" as Nasaq

// NASAQ screen frame: a border with rounded inner corners, drawn on the
// bottom layer (under windows, over the wallpaper) and only inside the
// window gaps, so it never moves or covers a window, and fullscreen hides it.
Item {
  id: root
  property var shell: null
  readonly property int thickness: Nasaq.Settings.get("frame.thickness", 6)
  readonly property int radius: Nasaq.Settings.get("frame.radius", 18)
  readonly property real alpha: Nasaq.Settings.get("frame.alpha", 0.9)

  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.namespace: "nasaq-frame"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}
      Canvas {
        id: canvas
        anchors.fill: parent
        readonly property color fill: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, root.alpha)
        onFillChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections { target: root; function onThicknessChanged() { canvas.requestPaint() } function onRadiusChanged() { canvas.requestPaint() } }
        onPaint: {
          var ctx = getContext("2d"), t = root.thickness, r = root.radius, w = width, h = height
          ctx.reset()
          ctx.fillStyle = fill
          ctx.beginPath()
          ctx.rect(0, 0, w, h)
          // inner rounded rectangle, drawn counter-clockwise so it becomes a hole
          ctx.moveTo(t + r, t)
          ctx.arcTo(t, t, t, t + r, r)
          ctx.lineTo(t, h - t - r)
          ctx.arcTo(t, h - t, t + r, h - t, r)
          ctx.lineTo(w - t - r, h - t)
          ctx.arcTo(w - t, h - t, w - t, h - t - r, r)
          ctx.lineTo(w - t, t + r)
          ctx.arcTo(w - t, t, w - t - r, t, r)
          ctx.closePath()
          ctx.fill("evenodd")
        }
      }
    }
  }
}
