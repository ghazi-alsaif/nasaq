import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.Commons
import "../nasaq.commons" as Nasaq

// NASAQ App Switcher. ALT + TAB calls `omarchy-shell nasaq.switcher next`
// (SHIFT + ALT + TAB → prev). While open the surface has the keyboard:
// TAB / SHIFT + TAB / arrows move, releasing ALT or Enter switches, Esc cancels.
// Turned off in NASAQ Settings, ALT + TAB behaves like stock Omarchy.
Item {
  id: root
  property var shell: null
  readonly property bool enabled: Nasaq.Settings.get("switcher.enabled", true)
  property bool open: false
  property var mru: []            // window addresses, most recent first
  property var items: []          // HyprlandToplevel snapshot while open
  property int index: 0

  function norm(a) { return String(a || "").replace(/^0x/, "") }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "activewindowv2") return
      var a = root.norm(event.data)
      if (!a) return
      var m = root.mru.filter(function(x) { return x !== a })
      m.unshift(a)
      root.mru = m.slice(0, 60)
    }
  }

  function snapshot() {
    var all = Hyprland.toplevels ? Hyprland.toplevels.values : []
    var live = []
    for (var i = 0; i < all.length; i++) {
      var ipc = all[i].lastIpcObject
      if (ipc && ipc.mapped !== false && !ipc.hidden && String(ipc.class || "") !== "") live.push(all[i])
    }
    live.sort(function(a, b) {
      var ia = root.mru.indexOf(root.norm(a.address)), ib = root.mru.indexOf(root.norm(b.address))
      return (ia < 0 ? 999 : ia) - (ib < 0 ? 999 : ib)
    })
    return live.slice(0, 12)
  }

  // Safety net: if the ALT release never reaches us, switch after a pause.
  Timer { id: idle; interval: 2500; onTriggered: root.confirm() }
  onOpenChanged: if (!open) idle.stop()

  function step(dir) {
    idle.restart()
    if (!enabled) {
      Quickshell.execDetached(["hyprctl", "dispatch", dir > 0 ? "hl.dsp.window.cycle_next()" : "hl.dsp.window.cycle_next({ next = false })"])
      Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.bring_to_top()"])
      return
    }
    if (!open) {
      Hyprland.refreshToplevels()
      items = snapshot()
      if (items.length < 2) { if (items.length === 1) activate(items[0]); return }
      index = dir > 0 ? 1 : items.length - 1
      open = true
      return
    }
    index = (index + dir + items.length) % items.length
  }
  function confirm() {
    if (!open) return
    var t = items[index]
    open = false
    if (t) activate(t)
  }
  function cancel() { open = false }
  function activate(t) {
    Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:0x" + norm(t.address)])
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.bring_to_top()"])
  }
  function iconFor(t) {
    var cls = t && t.lastIpcObject ? String(t.lastIpcObject.class || "") : ""
    var e = cls ? DesktopEntries.heuristicLookup(cls) : null
    return Quickshell.iconPath(e && e.icon ? e.icon : "application-x-executable", "application-x-executable")
  }

  IpcHandler {
    target: "nasaq.switcher"
    function next(): string { root.step(1); return "ok" }
    function prev(): string { root.step(-1); return "ok" }
    function cancel(): string { root.cancel(); return "ok" }
  }

  PanelWindow {
    id: win
    visible: root.open
    screen: Quickshell.screens.find(function(s) { return Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name }) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "nasaq-switcher"
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: root.cancel() }

    Item {
      id: keys
      focus: root.open
      Keys.onPressed: function(e) {
        if (e.key === Qt.Key_Escape) root.cancel()
        else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Right) root.step(1)
        else if (e.key === Qt.Key_Backtab || e.key === Qt.Key_Left) root.step(-1)
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.confirm()
        e.accepted = true
      }
      Keys.onReleased: function(e) { if (e.key === Qt.Key_Alt || e.key === Qt.Key_Meta) { root.confirm(); e.accepted = true } }
    }
    onVisibleChanged: if (visible) keys.forceActiveFocus()

    Rectangle {
      id: card
      anchors.centerIn: parent
      width: row.implicitWidth + 32
      height: row.implicitHeight + 32
      radius: 26
      color: Qt.rgba(0.11, 0.11, 0.12, Math.max(0.7, Nasaq.Theme.glassAlpha))
      border.color: Qt.rgba(1, 1, 1, 0.12)
      Row {
        id: row
        anchors.centerIn: parent
        spacing: 14
        Repeater {
          model: root.open ? root.items : []
          delegate: Column {
            id: cell
            required property var modelData
            required property int index
            readonly property bool current: index === root.index
            spacing: 8
            Rectangle {
              width: 220; height: 140; radius: 14
              color: Qt.rgba(1, 1, 1, cell.current ? 0.16 : 0.05)
              border.color: cell.current ? Color.accent : "transparent"
              border.width: 2
              clip: true
              ScreencopyView {
                anchors.fill: parent; anchors.margins: 6
                captureSource: root.open && cell.modelData.wayland ? cell.modelData.wayland : null
                live: false
              }
              IconImage { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 8; implicitSize: 34; source: root.iconFor(cell.modelData) }
              MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: root.index = cell.index; onClicked: { root.index = cell.index; root.confirm() } }
            }
            Text {
              width: 220
              horizontalAlignment: Text.AlignHCenter
              text: cell.modelData.title || (cell.modelData.lastIpcObject ? cell.modelData.lastIpcObject.class : "")
              elide: Text.ElideRight
              color: cell.current ? "white" : Qt.rgba(1, 1, 1, 0.6)
              font.family: Nasaq.Theme.textFont
              font.pixelSize: 13
              font.weight: cell.current ? Font.DemiBold : Font.Normal
            }
          }
        }
      }
    }
  }
}
