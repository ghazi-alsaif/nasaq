import QtQuick
import Quickshell
import Quickshell.Io
import "../../nasaq.commons"
import ".."

NPage {
  id: page
  title: Tr.t("page.windows")
  subtitle: "Window look, Mission Control and gaps."

  NSection {
    title: "MISSION CONTROL"
    NRow { title: "Open Mission Control"; subtitle: "SUPER + TAB"; NButton { text: "Open"; onClicked: Sys.ipc("nasaq.overview", "open") } }
    NRow { title: "App switcher (ALT + TAB)"; subtitle: "Live previews in most-recently-used order. Off = Omarchy's plain cycling."
      NSwitch { checked: Settings.get("switcher.enabled", true); onToggled: function(c) { Settings.set("switcher.enabled", c) } } }
    NRow { title: "Window gaps"; subtitle: "SUPER + SHIFT + BACKSPACE"; NButton { text: "Toggle"; onClicked: Sys.run("omarchy-hyprland-window-gaps-toggle") } }
  }

  property string spName: ""
  property string spCommand: ""
  property string spKey: ""
  Cmd { id: openClasses; script: "hyprctl clients -j | python3 -c 'import json,sys;print(json.dumps(sorted({c[\"class\"] for c in json.load(sys.stdin) if c[\"class\"]})))'" }
  property string ruleClass: ""
  property bool ruleFloat: true
  property int ruleW: 1000
  property int ruleH: 700
  property real ruleOpacity: 1
  function applyRules(list) { Settings.set("windowRules", list); rulesLater.restart() }
  Timer { id: rulesLater; interval: 600; onTriggered: Sys.run("nasaq-rules") }

  NSection {
    title: "WINDOW RULES (TEST)"
    note: "Make an app always open floating, at a size, centred, or with its own transparency."
    Repeater {
      model: Settings.get("windowRules", [])
      delegate: NRow {
        required property var modelData
        required property int index
        title: modelData.class
        subtitle: (modelData.float ? "Floating · " + modelData.width + "×" + modelData.height + " · centred" : "Tiled") + (modelData.opacity && modelData.opacity < 1 ? " · " + Math.round(modelData.opacity * 100) + "% opaque" : "")
        NButton { text: "Remove"; danger: true; onClicked: { var l = Settings.get("windowRules", []).slice(); l.splice(index, 1); page.applyRules(l) } }
      }
    }
    NRow {
      title: "App"
      subtitle: "From the windows open right now"
      Row { spacing: 8
        NDropdown { width: 240; model: (function() { try { return JSON.parse(openClasses.out || "[]") } catch (e) { return [] } })(); value: page.ruleClass; onActivated: function(v) { page.ruleClass = v } }
        NButton { text: "↻"; onClicked: openClasses.refresh() } }
    }
    NRow { title: "Open floating"; NSwitch { checked: page.ruleFloat; onToggled: function(c) { page.ruleFloat = c } } }
    NRow { title: "Width"; visible: page.ruleFloat; NSlider { width: 220; from: 300; to: 2200; stepSize: 20; value: page.ruleW; valueText: Math.round(value) + " px"; onMoved: function(v) { page.ruleW = Math.round(v) } } }
    NRow { title: "Height"; visible: page.ruleFloat; NSlider { width: 220; from: 200; to: 1300; stepSize: 20; value: page.ruleH; valueText: Math.round(value) + " px"; onMoved: function(v) { page.ruleH = Math.round(v) } } }
    NRow { title: "Opacity"; NSlider { width: 220; from: 0.3; to: 1; stepSize: 0.05; value: page.ruleOpacity; valueText: Math.round(value * 100) + "%"; onMoved: function(v) { page.ruleOpacity = v } } }
    NRow { title: ""; NButton { text: "Add rule"; primary: true; onClicked: {
      if (!page.ruleClass) return
      var l = Settings.get("windowRules", []).filter(function(r) { return r.class !== page.ruleClass })
      l.push({ class: page.ruleClass, float: page.ruleFloat, center: page.ruleFloat, width: page.ruleW, height: page.ruleH, opacity: page.ruleOpacity < 1 ? page.ruleOpacity : 0 })
      page.applyRules(l)
    } } }
  }

  NSection {
    title: "SCRATCHPADS"
    note: "A scratchpad is an app that slides in over whatever you are doing with one key, and hides again with the same key. It keeps running while hidden."
    Repeater {
      model: Settings.get("scratchpads", [])
      delegate: NRow {
        required property var modelData
        required property int index
        title: modelData.name + "  ·  " + (modelData.key || "no key")
        subtitle: modelData.command
        Row { spacing: 8
          NButton { text: "Show"; onClicked: Sys.run("nasaq-scratch " + modelData.name) }
          NButton { text: "Remove"; danger: true; onClicked: { var l = Settings.get("scratchpads", []).slice(); l.splice(index, 1); Settings.set("scratchpads", l); applyLater.restart() } } }
      }
    }
    NRow {
      title: "Add a scratchpad"
      subtitle: "Name, command, then click the key field and press the shortcut."
      Column { spacing: 6
        NTextField { width: 300; placeholder: "Name (e.g. notes)"; onEdited: function(t) { page.spName = t.trim().replace(/[^a-zA-Z0-9_-]/g, "") } }
        NTextField { width: 300; placeholder: "Command (e.g. obsidian)"; onEdited: function(t) { page.spCommand = t.trim() } }
        NKeyField { width: 300; combo: page.spKey; onCaptured: function(c) { page.spKey = c } }
        NButton { text: "Add"; primary: true; onClicked: {
          if (!page.spName || !page.spCommand) return
          var title = "NASAQ " + page.spName
          var cmd = page.spCommand
          var l = Settings.get("scratchpads", []).filter(function(x) { return x.name !== page.spName })
          // Windows are matched by class (the app id); ptyxis gets a fixed title instead.
          var entry = { name: page.spName, command: cmd, key: page.spKey, width: 1300, height: 760 }
          if (/^ptyxis\b/.test(cmd)) { entry.command = "ptyxis --standalone --new-window -T '" + title + "' -x " + JSON.stringify(cmd.replace(/^ptyxis\s*/, "") || "bash"); entry.title = title }
          else entry["class"] = ".*" + cmd.split(" ")[0].split("/").pop() + ".*"
          l.push(entry); Settings.set("scratchpads", l); applyLater.restart()
        } }
      }
    }
  }
  Timer { id: applyLater; interval: 600; onTriggered: Sys.run("nasaq-scratch apply") }

  NSection {
    id: corners
    title: "HOT CORNERS"
    note: "Rest the pointer in a corner to run the action."
    readonly property var choices: [
      { value: "none", label: "Nothing" }, { value: "overview", label: "Mission Control" }, { value: "desktop", label: "Desktop widgets" },
      { value: "spotlight", label: "Spotlight" }, { value: "notifcenter", label: "Notification Center" }, { value: "control", label: "Control Center" },
      { value: "island", label: "Expand island" }, { value: "menu", label: "Omarchy menu" }, { value: "screensaver", label: "Screensaver" }, { value: "lock", label: "Lock screen" }]
    Repeater {
      model: [{ c: "tl", t: "Top left" }, { c: "tr", t: "Top right" }, { c: "bl", t: "Bottom left" }, { c: "br", t: "Bottom right" }]
      delegate: NRow {
        required property var modelData
        title: modelData.t
        NDropdown {
          model: corners.choices
          value: Settings.get("hotCorners." + modelData.c, "none")
          onActivated: function(v) { Settings.set("hotCorners." + modelData.c, v) }
        }
      }
    }
    NRow {
      title: "Delay"
      NSlider { width: 220; from: 0; to: 800; stepSize: 50; value: Settings.get("hotCorners.delay", 150); valueText: Math.round(value) + " ms"
        onMoved: function(v) { Settings.set("hotCorners.delay", Math.round(v)) } }
    }
  }

  NSection {
    title: "WINDOW LOOK"
    note: "Transparency, blur, inactive dim, shadows and shape. Changes preview live and are written to ~/.config/hypr/nasaq-windows.lua."
    Item {
      width: parent.width
      height: look.item ? Math.max(420, look.item.implicitHeight || look.item.height || 420) : 60
      Loader {
        id: look
        width: Math.min(parent.width, 420)
        anchors.horizontalCenter: parent.horizontalCenter
        y: 8
        source: Qt.resolvedUrl("../../nasaq.windows/WindowLook.qml")
      }
      NSub { visible: look.status === Loader.Error; text: "The window look page (nasaq.windows) is missing." }
    }
  }
}
