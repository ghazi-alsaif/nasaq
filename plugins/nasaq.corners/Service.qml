import QtQuick
import Quickshell
import Quickshell.Wayland
import "../nasaq.commons" as Nasaq

// NASAQ hot corners: a 2×2 px hover target in each screen corner. The action
// fires after the pointer rests there for `hotCorners.delay` ms (default 150)
// with no button held, so dragging a window to an edge never triggers it.
Item {
  id: root
  property var shell: null

  readonly property var actions: ({
    "overview": ["omarchy-shell", "nasaq.overview", "toggle"],
    "desktop": ["omarchy-shell", "nasaq.desktop", "toggle"],
    "spotlight": ["omarchy-shell", "nasaq.spotlight", "toggle"],
    "notifcenter": ["omarchy-shell", "nasaq.notifcenter", "toggle"],
    "control": ["omarchy-shell", "nasaq.control-center", "toggle"],
    "island": ["omarchy-shell", "nasaq.island", "toggle"],
    "lock": ["omarchy-system-lock"],
    "screensaver": ["omarchy-launch-screensaver", "force"],
    "menu": ["omarchy-menu", "toggle"]
  })
  readonly property int delay: Nasaq.Settings.get("hotCorners.delay", 150)
  // No hot corners while a film or game is fullscreen.
  Nasaq.Fullscreen { id: fullscreen }
  function actionFor(corner) { return Nasaq.Settings.get("hotCorners." + corner, "none") }
  function fire(corner) {
    var a = actions[actionFor(corner)]
    if (a) Quickshell.execDetached(a)
  }

  // One set of corner windows per screen × corner (Variants, because a
  // Repeater cannot create windows).
  readonly property var cornerModel: {
    var out = []
    var screens = Quickshell.screens
    var defs = [{ c: "tl", top: true, left: true }, { c: "tr", top: true, left: false }, { c: "bl", top: false, left: true }, { c: "br", top: false, left: false }]
    for (var i = 0; i < screens.length; i++)
      for (var j = 0; j < defs.length; j++)
        out.push({ screen: screens[i], c: defs[j].c, top: defs[j].top, left: defs[j].left })
    return out
  }

  Variants {
    model: root.cornerModel
    PanelWindow {
      id: cornerWin
      required property var modelData
      readonly property string corner: modelData.c
      visible: root.actionFor(corner) !== "none" && !fullscreen.active
      screen: modelData.screen
      anchors { top: modelData.top; bottom: !modelData.top; left: modelData.left; right: !modelData.left }
      implicitWidth: 2
      implicitHeight: 2
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "nasaq-hot-corner"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onContainsMouseChanged: containsMouse && !pressed ? armed.restart() : armed.stop()
        onPressedChanged: if (pressed) armed.stop()
      }
      Timer { id: armed; interval: root.delay; onTriggered: if (area.containsMouse && !area.pressed) root.fire(cornerWin.corner) }
    }
  }
}
