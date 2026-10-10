import QtQuick
import Quickshell
import Quickshell.Io
import "../../nasaq.commons"
import ".."

NPage {
  id: page
  title: Tr.t("page.shortcuts")
  subtitle: "NASAQ shortcuts use key codes, so they work under the Arabic layout too."

  Cmd { id: arabic; script: "nasaq-arabic-binds status" }

  NSection {
    title: "ARABIC LAYOUT"
    note: "Hyprland matches letter shortcuts by the typed character, so under the Arabic layout SUPER + W and friends stop working. This re-creates every letter shortcut on its physical key."
    NRow {
      title: "Shortcuts work under the Arabic layout"
      subtitle: "Regenerate after an Omarchy update adds new shortcuts."
      Row {
        spacing: 10
        NButton { text: "Regenerate"; visible: arabic.out === "on"; onClicked: { Sys.run("nasaq-arabic-binds on") } }
        NSwitch { anchors.verticalCenter: parent.verticalCenter; checked: arabic.out === "on"
          onToggled: function(c) { Sys.run("nasaq-arabic-binds " + (c ? "on" : "off")); arabic.out = c ? "on" : "off"; Settings.set("shortcuts.arabicSafe", c) } }
      }
    }
  }

  Cmd { id: keysList; script: "nasaq-keys list"; onDone: function(o) { try { page.rows = JSON.parse(o) } catch (e) { page.rows = [] } } }
  Cmd { id: keysAct; autoRun: false; onDone: function(o) { page.message = o; keysList.refresh() } }
  property var rows: []
  property string filter: ""
  property string editing: ""
  property string message: ""
  function run(args) { page.message = "…"; keysAct.script = "nasaq-keys " + args + " 2>&1"; keysAct.refresh() }
  function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
  readonly property var shown: rows.filter(function(r) {
    if (!filter) return true
    return (r.keys + " " + r.description).toLowerCase().indexOf(filter) !== -1
  })

  NSection {
    title: "ALL SHORTCUTS · " + page.rows.length
    note: page.message ? page.message : "Click Change, then press the new keys. Keys already in use are refused and the owner is shown. Changes survive Omarchy updates."
    NRow {
      title: "Search"
      NTextField { width: 300; placeholder: "e.g. close, browser, SUPER + W"; onEdited: function(t) { page.filter = t.toLowerCase().trim() } }
    }
    Repeater {
      model: page.shown
      delegate: NRow {
        required property var modelData
        title: modelData.description
        subtitle: modelData.keys + (modelData.changed ? "   (was " + modelData.changed + ")" : "")
        Row {
          spacing: 8
          NKeyField {
            visible: page.editing === modelData.keys
            width: 230
            onCaptured: function(c) { page.editing = ""; page.run("set " + page.q(modelData.changed || modelData.keys) + " " + page.q(c)) }
          }
          NButton { visible: page.editing !== modelData.keys; text: "Change"; onClicked: page.editing = modelData.keys }
          NButton { visible: !!modelData.changed; text: "Reset"; onClicked: page.run("reset " + page.q(modelData.changed)) }
          NButton { visible: page.editing !== modelData.keys && !modelData.changed; text: "Off"; danger: true; onClicked: page.run("set " + page.q(modelData.keys) + " ''") }
        }
      }
    }
  }

  NSection {
    title: "FILES"
    NRow { title: "Searchable list of every binding"; subtitle: "SUPER + K"; NButton { text: "Show"; onClicked: Sys.run("omarchy menu keybindings") } }
    NRow { title: "Personal bindings file"; subtitle: "~/.config/hypr/bindings.lua"; NButton { text: "Edit"; onClicked: Sys.edit(Sys.home + "/.config/hypr/bindings.lua") } }
  }
}
