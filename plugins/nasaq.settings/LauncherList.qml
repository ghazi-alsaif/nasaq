pragma ComponentBehavior: Bound
import QtQuick
import "../nasaq.commons"

// Add / edit / remove the bar launchers stored at one settings key.
//   LauncherList { key: "bars.extraLaunchers" }
// Items: { glyph | svg, tooltip, command, rightCommand?, terminal? }. Fields the
// form does not show (svg) are kept when a row is edited.
Column {
  id: ed
  property string key: ""
  property var fallback: []        // listed (and edited from) while the key is unset or empty
  readonly property var items: {
    var l = Settings.get(key, null)
    return Array.isArray(l) && l.length ? l : fallback
  }
  property int editing: -1         // row in the form; items.length = a new row
  width: parent ? parent.width : 400

  function startEdit(i) {
    var it = i < items.length ? items[i] : {}
    fGlyph.text = it.glyph || ""
    fTooltip.text = String(it.tooltip || "").replace(/\n/g, "\\n")
    fCommand.text = it.command || ""
    fRight.text = it.rightCommand || ""
    fTerminal.checked = !!it.terminal
    editing = i
  }
  function commit() {
    if (!fCommand.text.trim()) return
    var l = items.slice()
    var it = Object.assign({}, editing < l.length ? l[editing] : {})
    if (fGlyph.text.trim()) it.glyph = fGlyph.text.trim(); else delete it.glyph
    it.tooltip = fTooltip.text.trim().replace(/\\n/g, "\n") || fCommand.text.trim()
    it.command = fCommand.text.trim()
    if (fRight.text.trim()) it.rightCommand = fRight.text.trim(); else delete it.rightCommand
    if (fTerminal.checked) it.terminal = true; else delete it.terminal
    if (editing < l.length) l[editing] = it; else l.push(it)
    Settings.set(key, l)
    editing = -1
  }

  Repeater {
    model: ed.items
    delegate: NRow {
      id: launcherRow
      required property var modelData
      required property int index
      title: (modelData.glyph ? modelData.glyph + "  " : "") + String(modelData.tooltip || modelData.command).split("\n")[0]
      subtitle: modelData.command + (modelData.rightCommand ? "  ·  right-click: " + modelData.rightCommand : "")
                + (modelData.terminal ? "  ·  terminal" : "")
      Row {
        spacing: 8
        NButton { text: "Edit"; onClicked: ed.startEdit(launcherRow.index) }
        NButton { text: "Remove"; danger: true
          onClicked: { var l = ed.items.slice(); l.splice(launcherRow.index, 1); Settings.set(ed.key, l); ed.editing = -1 } }
      }
    }
  }

  Column {
    width: parent.width
    visible: ed.editing >= 0
    NRow { title: "Icon"; subtitle: "A Nerd Font glyph"; NTextField { id: fGlyph; width: 80 } }
    NRow { title: "Tooltip"; subtitle: "\\n starts a new line"; NTextField { id: fTooltip; width: 320 } }
    NRow { title: "Command"; NTextField { id: fCommand; width: 320; placeholder: "omarchy-launch-browser" } }
    NRow { title: "Right-click command"; subtitle: "Optional"; NTextField { id: fRight; width: 320 } }
    NRow { title: "Open in a terminal"; NSwitch { id: fTerminal; onToggled: function(c) { checked = c } } }
    NRow {
      title: ""
      Row {
        spacing: 8
        NButton { text: "Cancel"; onClicked: ed.editing = -1 }
        NButton { text: "Save"; primary: true; onClicked: ed.commit() }
      }
    }
  }

  NRow {
    title: "Add a launcher"
    visible: ed.editing < 0
    NButton { text: "Add"; primary: true; onClicked: ed.startEdit(ed.items.length) }
  }
}
