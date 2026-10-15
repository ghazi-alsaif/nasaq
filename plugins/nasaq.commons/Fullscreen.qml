import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// True while the focused window is fullscreen (a film, a game), so NASAQ can
// stay out of the way: no toasts or chimes, no hot corners. Maximised windows
// (Hyprland fullscreen mode 1) do not count.
// Usage: Nasaq.Fullscreen { id: fs }  then  fs.active
Item {
  id: root
  visible: false
  property bool active: false

  function refresh() { if (!probe.running) probe.running = true }

  Process {
    id: probe
    command: ["hyprctl", "activewindow", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.active = Number(JSON.parse(this.text || "{}").fullscreen || 0) > 1 } catch (e) { root.active = false }
      }
    }
  }
  // Events arrive in bursts (a fullscreen switch also moves focus), so ask once after they settle.
  Timer { id: settle; interval: 60; onTriggered: root.refresh() }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var n = event.name
      if (n === "fullscreen" || n === "activewindowv2" || n === "workspacev2" || n === "focusedmonv2" || n === "closewindow")
        settle.restart()
    }
  }
  Component.onCompleted: refresh()
}
