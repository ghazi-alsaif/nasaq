import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.Ui
import qs.Commons
import "../nasaq.commons" as Nasaq

// NASAQ: the window-look settings (WindowLook.qml) in a bar island. The same
// settings are also a page in the control center.
BarWidget {
  id: root
  moduleName: "nasaq.windows"

  property bool opened: false
  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  function open() { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened }

  IpcHandler {
    target: "nasaq.windows"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    // Opens straight onto one section, e.g. `omarchy-shell nasaq.windows section blur`.
    function section(name: string): void { look.page = name; root.open() }
  }

  // ── Bar pill ───────────────────────────────────────────────────────
  implicitWidth: pill.width
  implicitHeight: Style.bar.iconSlot

  Rectangle {
    id: pill
    anchors.verticalCenter: parent.verticalCenter
    width: height + 6
    height: Math.round(Style.bar.iconSlot * 0.82)
    radius: height / 2
    opacity: root.pillHidden ? 0 : 1
    color: Util.alpha(root.barForeground, root.opened ? 0.24 : (pillMouse.containsMouse ? 0.16 : 0.08))
    Behavior on color { Nasaq.NColour { duration: Nasaq.Motion.micro } }

    Text {
      anchors.centerIn: parent
      text: "󰖲"
      color: root.barForeground
      font.family: Style.font.family
      font.pixelSize: Style.bar.iconFont
    }

    MouseArea {
      id: pillMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggle()
    }
  }

  property bool overlayShown: false
  // The bar pill hides once the card has painted its identical lookalike and
  // shows again before the card unmaps, so the handoff never flashes.
  property bool pillHidden: false
  onOpenedChanged: {
    if (opened) { collapseHide.stop(); handoffOut.stop(); overlayShown = true; handoffIn.restart() }
    else { handoffIn.stop(); collapseHide.restart() }
  }
  Timer { id: handoffIn; interval: 32; onTriggered: root.pillHidden = true }
  // Unmap right after the fixed-length close (Nasaq.Motion.close).
  Timer { id: collapseHide; interval: Nasaq.Motion.close + 40; onTriggered: { root.pillHidden = false; handoffOut.restart() } }
  Timer { id: handoffOut; interval: 32; onTriggered: { root.overlayShown = false; look.page = "" } }

  // ── The card grows out of the pill, like the control center ──────
  PanelWindow {
    id: overlay
    screen: pill.QsWindow.window ? pill.QsWindow.window.screen : null
    visible: root.overlayShown
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nasaq-windows"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    readonly property point pillPos: {
      var unused = pill.width + root.width + overlay.width
      var w = pill.QsWindow.window
      var p = pill.mapToItem(null, 0, 0)
      var ml = w && w.margins ? (w.margins.left || 0) : 0
      var mt = w && w.margins ? (w.margins.top || 0) : 0
      return Qt.point(p.x + ml, p.y + mt)
    }
    readonly property real pillRight: pillPos.x + pill.width

    MouseArea {
      anchors.fill: parent
      enabled: root.opened
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: root.close()
    }

    Item {
      anchors.fill: parent
      focus: root.opened
      Keys.onEscapePressed: root.close()
    }

    Rectangle {
      id: shape
      readonly property real openW: 340
      readonly property real openH: Math.min(look.implicitHeight + 24, overlay.height - overlay.pillPos.y - 20)
      y: overlay.pillPos.y
      width: root.opened ? openW : pill.width
      height: root.opened ? openH : pill.height
      x: Math.max(Style.gapsOut + 4, Math.min(overlay.pillRight, overlay.width - Style.gapsOut - 4) - width)
      radius: root.opened ? 24 : pill.height / 2
      // Closed, the card fades out as transparent glass rather than turning into
      // the pill's light tint: interpolating dark glass towards a light tint
      // passed through light greys, a visible flash while closing. The bar
      // pill shows its own tint again at the end of the close.
      color: root.opened ? Util.alpha(Color.background, Math.max(0.55, Nasaq.Theme.glassAlpha)) : Util.alpha(Color.background, 0)
      border.color: Qt.rgba(1, 1, 1, root.opened ? 0.14 : 0)
      border.width: 1
      clip: true
      // One curve and length for size and corners, so the card arrives as one piece.
      readonly property string motionKind: root.opened ? "open" : "close"
      Behavior on width { Nasaq.NAnim { kind: shape.motionKind } }
      Behavior on height { Nasaq.NAnim { kind: shape.motionKind } }
      Behavior on radius { Nasaq.NAnim { kind: shape.motionKind } }
      Behavior on color { Nasaq.NColour {} }

      MouseArea { anchors.fill: parent }

      Flickable {
        anchors.fill: parent
        anchors.margins: 12
        contentHeight: look.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        opacity: root.opened ? 1 : 0
        Behavior on opacity { SequentialAnimation { PauseAnimation { duration: root.opened ? Math.round(Nasaq.Motion.open * 0.3) : 0 } Nasaq.NFade {} } }

        WindowLook {
          id: look
          width: 340 - 24
        }
      }
    }
  }
}
