import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.Ui
import qs.Commons
import "../nasaq.lock" as Lock
import "../nasaq.commons" as Nasaq

// NASAQ: the lock screen's control center, summoned from the bar. The card
// lives in its own overlay so it keeps its exact look; clicking outside
// it (or Escape) closes it.
BarWidget {
  id: root
  moduleName: "nasaq.control-center"

  // Own open state: the shared panel controller closed the card on the press
  // and the click then reopened it, so a second click never dismissed it.
  property bool opened: false
  // Glass: the card is as see-through as the user's active windows (Control
  // Center > Windows > Transparency), and Hyprland blurs behind it (layer rule
  // in looknfeel.lua), so it follows the user's window settings like everything else.
  property real glassAlpha: 0.65
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/nasaq/windows.json"
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try { var a = Number(JSON.parse(text()).activeOpacity); if (isFinite(a)) root.glassAlpha = Math.max(0.2, Math.min(1, a)) } catch (e) {}
    }
  }
  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  function open() { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened }

  IpcHandler {
    target: "nasaq.control-center"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    // Opens straight onto the Sound page.
    function sound(): void { root.open(); controls.openPage("sound") }
    function windows(): void { root.open(); controls.openPage("windows") }
    // e.g. `omarchy-shell nasaq.control-center windowsSection shadows`
    function windowsSection(name: string): void { root.open(); controls.openWindowsSection(name) }
  }

  implicitWidth: pill.width
  implicitHeight: Style.bar.iconSlot

  // Same status pill as the lock screen: layout · Wi-Fi · battery · toggles.
  Rectangle {
    id: pill
    anchors.verticalCenter: parent.verticalCenter
    width: pillRow.implicitWidth + 18
    opacity: root.pillHidden ? 0 : 1
    height: Math.round(Style.bar.iconSlot * 0.82)
    radius: height / 2
    color: Util.alpha(root.barForeground, root.opened ? 0.24 : (pillMouse.containsMouse ? 0.16 : 0.08))
    Behavior on color { Nasaq.NColour { duration: Nasaq.Motion.micro } }

    Row {
      id: pillRow
      anchors.centerIn: parent
      spacing: 10

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: text.length > 0
        text: controls.layoutShort
        color: root.barForeground
        font.family: Nasaq.Theme.textFont
        font.weight: Font.DemiBold
        font.pixelSize: Math.round(Style.bar.iconFont * 0.8)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: controls.wifiIcon
        color: root.barForeground
        font.family: Style.font.family
        font.pixelSize: Style.bar.iconFont
      }
      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        visible: controls.batteryPercent >= 0
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: controls.batteryPercent + "%"
          color: root.barForeground
          font.family: Nasaq.Theme.textFont
          font.pixelSize: Math.round(Style.bar.iconFont * 0.8)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: controls.batteryIcon
          // Yellow while in Saver mode.
          color: controls.powerProfile === "power-saver" ? Nasaq.Theme.warn : root.barForeground
          font.family: Style.font.family
          font.pixelSize: Style.bar.iconFont
        }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "󰔡"
        color: root.barForeground
        font.family: Style.font.family
        font.pixelSize: Style.bar.iconFont
      }
    }

    MouseArea {
      id: pillMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggle()
    }
  }

  // Kept mapped while the island shrinks back into the pill.
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
  Timer { id: handoffOut; interval: 32; onTriggered: { root.overlayShown = false } }
  Timer { id: leaveTimer; interval: 650; onTriggered: root.close() }

  // ── The card grows out of the pill, like the island ──────
  PanelWindow {
    id: overlay
    screen: pill.QsWindow.window ? pill.QsWindow.window.screen : null
    visible: root.overlayShown
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nasaq-control-center"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Where the pill sits, in screen coordinates.
    readonly property point pillPos: {
      var unused = pill.width + root.width + overlay.width
      // The floating bar window sits inset from the screen edges.
      var w = pill.QsWindow.window
      var p = pill.mapToItem(null, 0, 0)
      var ml = w && w.margins ? (w.margins.left || 0) : 0
      var mt = w && w.margins ? (w.margins.top || 0) : 0
      return Qt.point(p.x + ml, p.y + mt)
    }
    readonly property real pillRight: pillPos.x + pill.width
    // The bar's own right edge: the open card lines up with it instead of
    // leaving a sliver of bar sticking out beside the card.
    readonly property real barRight: {
      var w = pill.QsWindow.window
      return w ? ((w.margins ? (w.margins.left || 0) : 0) + w.width) : pillRight
    }

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
      readonly property real openW: controls.width
      readonly property real openH: controls.targetHeight
      y: overlay.pillPos.y
      width: root.opened ? openW : pill.width
      height: root.opened ? openH : pill.height
      // Grow leftward from the pill's right edge, staying on screen.
      x: Math.min(root.opened ? overlay.barRight : overlay.pillRight, overlay.width - Style.gapsOut - 4) - width
      radius: root.opened ? 24 : pill.height / 2
      color: root.opened ? Nasaq.Theme.glass : Util.alpha(root.barForeground, pillMouse.containsMouse ? 0.16 : 0.08)
      border.color: Qt.rgba(1, 1, 1, root.opened ? 0.14 : 0)
      border.width: 1
      clip: true
      // One curve and length for size and corners, so the card arrives as one piece.
      readonly property string motionKind: root.opened ? "open" : "close"
      Behavior on width { Nasaq.NAnim { kind: shape.motionKind } }
      Behavior on height { Nasaq.NAnim { kind: shape.motionKind } }
      Behavior on radius { Nasaq.NAnim { kind: shape.motionKind } }
      Behavior on color { Nasaq.NColour {} }

      // Swallow clicks inside the island so they don't close it.
      MouseArea { anchors.fill: parent }
      // Like the island: the card closes shortly after the pointer leaves it
      // (not while a Wi-Fi password is being typed).
      HoverHandler {
        onHoveredChanged: {
          if (hovered) leaveTimer.stop()
          else if (root.opened && !controls.promptSsid) leaveTimer.restart()
        }
      }

      Lock.ControlCenter {
        id: controls
        anchors.top: parent.top
        anchors.right: parent.right
        textFont: Nasaq.Theme.textFont
        iconFont: Style.font.family
        panelRadius: Nasaq.Theme.radiusPanel
        active: true
        interactive: true
        opened: root.opened
        motionScale: Nasaq.Motion.scale
        showLock: true
        chromeless: true
        onCloseRequested: root.close()
      }
    }
  }
}
