import QtQuick
import Quickshell
import Quickshell.Io
import "../../nasaq.commons"
import ".."

NPage {
  id: page
  title: Tr.t("page.plugins")
  subtitle: "Turn any shell plugin on or off. NASAQ, Omarchy's built-ins and community plugins all use Omarchy's own plugin system."

  // Plugins NASAQ needs to run: shown locked instead of with a switch.
  readonly property var essential: ["nasaq.commons", "nasaq.settings", "nasaq.bar", "nasaq.island", "nasaq.notifications", "nasaq.lock",
    "omarchy.menu", "omarchy.polkit", "omarchy.idle", "omarchy.background", "omarchy.battery"]
  // One service per job: enabling the left one while the right one runs would start two.
  readonly property var owners: ({ "omarchy.notifications": "nasaq.notifications", "omarchy.lock": "nasaq.lock", "omarchy.osd": "nasaq.island",
    "omarchy.tray": "nasaq.tray", "omarchy.workspaces": "nasaq.workspaces" })

  property var plugins: []
  property string busy: ""
  property string message: ""

  Cmd {
    id: list
    script: "omarchy plugin list --json 2>/dev/null | python3 -c '\nimport json,sys,os,glob\nd=json.load(sys.stdin)\ndesc={}\nfor m in glob.glob(os.path.expanduser(\"~/.config/omarchy/plugins/*/manifest.json\"))+glob.glob(\"/usr/share/omarchy/shell/plugins/**/*manifest.json\",recursive=True):\n  try:\n    j=json.load(open(m)); desc[j[\"id\"]]=j.get(\"description\",\"\")\n  except Exception: pass\nfor p in d: p[\"description\"]=desc.get(p[\"id\"],\"\")\nprint(json.dumps(d))'"
    onDone: function(o) { try { page.plugins = JSON.parse(o) } catch (e) { page.plugins = [] } page.busy = "" }
  }
  Cmd {
    id: act
    autoRun: false
    onDone: function(o) { page.message = o.split("\n").pop(); list.refresh() }
  }
  function setEnabled(id, on) {
    if (on && owners[id] && isEnabled(owners[id])) {
      message = id + " is handled by " + owners[id] + ". Turn that off first."
      return
    }
    busy = id
    // Omarchy keeps an external plugin's "off" by dropping it from shell.json, so
    // the doctor would read it as missing and put it back; the choice is noted here too.
    var off = (Settings.get("plugins.off", []) || []).filter(function(x) { return x !== id })
    if (!on && id.indexOf("nasaq.") === 0) off.push(id)
    Settings.set("plugins.off", off)
    act.script = "omarchy plugin " + (on ? "enable " : "disable ") + id + " 2>&1"
    act.refresh()
  }
  function isEnabled(id) { for (var i = 0; i < plugins.length; i++) if (plugins[i].id === id) return plugins[i].enabled; return false }
  function group(which) {
    return plugins.filter(function(p) {
      if (which === "nasaq") return p.id.indexOf("nasaq.") === 0
      if (which === "omarchy") return p.firstParty
      return !p.firstParty && p.id.indexOf("nasaq.") !== 0
    }).sort(function(a, b) { return (b.enabled - a.enabled) || a.name.localeCompare(b.name) })
  }

  NSection {
    title: "ACTIONS"
    note: page.message
    NRow {
      title: "Rescan plugins"
      subtitle: "Picks up plugins added or edited on disk."
      NButton { text: Tr.t("common.reload"); onClicked: { Sys.run("omarchy-shell shell rescanPlugins"); list.refresh() } }
    }
    NRow {
      title: "Add a plugin from git"
      subtitle: "Uses `omarchy plugin add`; the plugin lands disabled until you turn it on here."
      NButton { text: "Add…"; onClicked: Sys.term("read -rp 'Git URL: ' u && omarchy plugin add \"$u\"; read -n1 -p 'Press any key'") }
    }
  }

  Repeater {
    model: [{ key: "nasaq", title: "NASAQ" }, { key: "other", title: "COMMUNITY" }, { key: "omarchy", title: "OMARCHY BUILT-IN" }]
    delegate: NSection {
      id: sec
      required property var modelData
      readonly property var items: page.group(modelData.key)
      visible: items.length > 0
      title: modelData.title + "  ·  " + items.filter(function(p) { return p.enabled }).length + " on / " + items.length
      Repeater {
        model: sec.items
        delegate: NRow {
          required property var modelData
          readonly property bool locked: page.essential.indexOf(modelData.id) !== -1
          readonly property bool isBar: (modelData.kinds || []).indexOf("bar") !== -1
          title: modelData.name + (modelData.clonedFrom ? "  (copy of " + modelData.clonedFrom + ")" : "")
          subtitle: modelData.id + "  ·  " + (modelData.kinds || []).join(", ") + (modelData.description ? "\n" + modelData.description : "")
          Row {
            spacing: 10
            NSub { anchors.verticalCenter: parent.verticalCenter; visible: locked || isBar || page.busy === modelData.id
                   text: page.busy === modelData.id ? "…" : locked ? "Required" : "Bar (choose in Bars)" }
            NSwitch {
              anchors.verticalCenter: parent.verticalCenter
              visible: !locked && !isBar
              checked: modelData.enabled
              enabledState: page.busy === ""
              onToggled: function(c) { page.setEnabled(modelData.id, c) }
            }
          }
        }
      }
    }
  }
}
