import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "../nasaq.commons" as Nasaq

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  // The focused workspace keeps the filled square the built-in widget paints,
  // but with its number cut out of it (Material Design "numeric-N-box" glyphs),
  // so the current workspace stays readable. Index 0 is workspace 10, which the
  // bar labels "0". The codepoints are not evenly spaced: 5 onwards shift by one.
  readonly property var numberBoxes: [
    "\uDB80\uDFA1", "\uDB80\uDFA4", "\uDB80\uDFA7", "\uDB80\uDFAA", "\uDB80\uDFAD",
    "\uDB80\uDFB1", "\uDB80\uDFB3", "\uDB80\uDFB6", "\uDB80\uDFB9", "\uDB80\uDFBC"
  ]

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)
  readonly property bool showIcons: Nasaq.Settings.get("workspaces.appIcons", true) !== false

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  // Wheel over the numbers moves to the next or previous workspace. Deltas are
  // collected to one notch (120) so a touchpad does not skip several at once.
  // A MouseArea on top that takes only the wheel (clicks pass to the numbers),
  // like the island's volume wheel: the WheelHandler never received the events
  // under the bar's own mouse areas.
  property real wheelAcc: 0
  MouseArea {
    anchors.fill: parent
    z: 10
    acceptedButtons: Qt.NoButton
    onWheel: function(wheel) {
      root.wheelAcc += wheel.angleDelta.y || -wheel.angleDelta.x
      wheel.accepted = true
      if (Math.abs(root.wheelAcc) < 120 || !root.bar) return
      var step = root.wheelAcc > 0 ? "-1" : "+1"
      root.wheelAcc = 0
      root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"r" + step + "\" })"))
    }
  }

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      // The number, then (horizontal bars, Settings › Workspaces & Windows ›
      // App icons) the icons of up to three apps open on that workspace.
      Item {
        id: cell
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
        readonly property var appIcons: {
          if (!root.showIcons || root.vertical || !workspace) return []
          var seen = {}, out = []
          var tls = workspace.toplevels.values
          for (var i = 0; i < tls.length; i++) {
            var t = tls[i]
            var id = t.wayland && t.wayland.appId ? String(t.wayland.appId) : (t.lastIpcObject && t.lastIpcObject["class"] ? String(t.lastIpcObject["class"]) : "")
            if (!id || seen[id]) continue
            seen[id] = true
            var de = DesktopEntries.heuristicLookup(id)
            var icon = de && de.icon ? Quickshell.iconPath(de.icon, "") : ""
            if (icon) out.push(icon)
            if (out.length >= 3) break
          }
          return out
        }

        implicitWidth: number.implicitWidth + (icons.width > 0 ? icons.width + 2 : 0)
        implicitHeight: root.barSize
        Behavior on implicitWidth { Nasaq.NAnim { kind: "move" } }

        WidgetButton {
          id: number
          anchors.left: parent.left
          bar: root.bar
          text: cell.focused ? root.numberBoxes[cell.modelData % 10] : (cell.modelData === 10 ? "0" : String(cell.modelData))
          opacity: cell.occupied || cell.focused ? 1 : 0.5
          horizontalMargin: 6
          verticalPadding: 6
          fixedWidth: root.vertical ? root.barSize : Style.space(20)
          fixedHeight: root.barSize
          onPressed: function() { root.focusWorkspace(cell.modelData) }
        }
        Row {
          id: icons
          anchors.left: number.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 3
          opacity: cell.focused ? 1 : 0.7
          Repeater {
            model: cell.appIcons
            Image {
              required property string modelData
              width: 14; height: 14
              anchors.verticalCenter: parent.verticalCenter
              source: modelData
              sourceSize: Qt.size(28, 28)
              smooth: true
              mipmap: true
            }
          }
        }
        MouseArea { anchors.fill: icons; cursorShape: Qt.PointingHandCursor; onClicked: root.focusWorkspace(cell.modelData) }
      }
    }
  }
}
