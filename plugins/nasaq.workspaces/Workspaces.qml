import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

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

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  // Wheel over the numbers moves to the next or previous workspace. Deltas are
  // collected to one notch (120) so a touchpad does not skip several at once.
  property real wheelAcc: 0
  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(event) {
      root.wheelAcc += event.angleDelta.y || -event.angleDelta.x
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

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        bar: root.bar
        text: focused ? root.numberBoxes[modelData % 10] : (modelData === 10 ? "0" : String(modelData))
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
      }
    }
  }
}
