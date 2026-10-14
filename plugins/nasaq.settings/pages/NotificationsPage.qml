import QtQuick
import Quickshell
import Quickshell.Io
import "../../nasaq.commons"
import ".."

NPage {
  id: page
  title: Tr.t("page.notifications")
  subtitle: "Every notification appears from the island."

  Cmd { id: dnd; script: "omarchy-shell notifications dndState" }
  property bool soundsOff: false
  FileView {
    path: Sys.home + "/.config/omarchy/nasaq/sounds-off"; printErrors: false; watchChanges: true
    onFileChanged: reload()
    onLoaded: page.soundsOff = true
    onLoadFailed: page.soundsOff = false
  }

  NSection {
    title: "BEHAVIOUR"
    NRow {
      title: "Do Not Disturb"
      subtitle: "Silences popups; everything still lands in the history. SUPER + CTRL + ,"
      NSwitch { checked: dnd.out === "on"; onToggled: function(c) { Sys.ipc("notifications", "setDnd", c ? "on" : "off"); dnd.out = c ? "on" : "off" } }
    }
    NRow {
      title: "Show each notification for"
      subtitle: "Low-priority ones go a little sooner; critical alerts stay until dismissed. Hovering the island pauses it."
      NSlider { width: 220; from: 2; to: 30; stepSize: 1; value: Settings.get("notifications.duration", 8); valueText: Math.round(value) + " s"
        onMoved: function(v) { Settings.set("notifications.duration", Math.round(v)) } }
    }
    NRow {
      title: "Send a test notification"
      NButton { text: "Test"; onClicked: Sys.run("notify-send -a NASAQ 'NASAQ' 'This is how notifications look.'") }
    }
    NRow {
      title: "NASAQ sounds"
      subtitle: "Notification, lock and volume sounds."
      NSwitch {
        checked: !page.soundsOff
        onToggled: function(c) {
          Sys.run(c ? "rm -f ~/.config/omarchy/nasaq/sounds-off" : "mkdir -p ~/.config/omarchy/nasaq && touch ~/.config/omarchy/nasaq/sounds-off")
          page.soundsOff = !c
        }
      }
    }
  }
  Cmd {
    id: apps
    script: "python3 -c 'import json,glob,os\nseen=[]\nfor f in sorted(glob.glob(os.path.expanduser(\"~/.local/state/omarchy/notifications/**/*.json\"),recursive=True),key=os.path.getmtime,reverse=True):\n  try: a=json.load(open(f)).get(\"app\",\"\")\n  except Exception: continue\n  if a and a not in seen: seen.append(a)\nprint(json.dumps(seen[:30]))'"
  }
  readonly property var appList: { try { return JSON.parse(apps.out || "[]") } catch (e) { return [] } }
  property string newApp: ""
  property string newAction: "mute"
  property int newValue: 15
  readonly property var actionLabels: ({ block: "Block completely", mute: "History only (no popup)", silent: "No sound", pin: "Keep until dismissed", duration: "Show longer" })

  NSection {
    title: "PER-APP RULES"
    note: "Rules apply before Do Not Disturb. Apps that sent notifications recently are listed."
    NRow {
      title: "Group by app in the Notification Center"
      NSwitch { checked: Settings.get("notifications.groupByApp", true); onToggled: function(c) { Settings.set("notifications.groupByApp", c) } }
    }
    Repeater {
      model: Settings.get("notifications.rules", [])
      delegate: NRow {
        required property var modelData
        required property int index
        title: modelData.app
        subtitle: page.actionLabels[modelData.action] + (modelData.action === "duration" ? " (" + modelData.value + " s)" : "")
        NButton { text: "Remove"; danger: true
          onClicked: { var r = Settings.get("notifications.rules", []).slice(); r.splice(index, 1); Settings.set("notifications.rules", r) } }
      }
    }
    NRow {
      title: "Add a rule"
      Row {
        spacing: 8
        NDropdown { width: 170; model: page.appList; value: page.newApp; onActivated: function(v) { page.newApp = v } }
        NDropdown { width: 200; model: Object.keys(page.actionLabels).map(function(k) { return { value: k, label: page.actionLabels[k] } }); value: page.newAction; onActivated: function(v) { page.newAction = v } }
        NButton { text: "Add"; primary: true; onClicked: {
          if (!page.newApp) return
          var r = Settings.get("notifications.rules", []).filter(function(x) { return x.app !== page.newApp })
          r.push({ app: page.newApp, action: page.newAction, value: page.newValue })
          Settings.set("notifications.rules", r)
        } }
      }
    }
  }

  NSection {
    title: "HISTORY"
    NRow { title: "Notification Center"; subtitle: "SUPER + N"; NButton { text: "Open"; onClicked: Sys.ipc("nasaq.notifcenter", "open") } }
    NRow { title: "Clear all notifications"; NButton { text: "Clear"; danger: true; onClicked: Sys.ipc("notifications", "clear") } }
  }
}
