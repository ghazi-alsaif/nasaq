import QtQuick
import Quickshell
import Quickshell.Io
import "../../nasaq.commons"
import ".."

NPage {
  id: page
  title: Tr.t("page.bars")
  subtitle: "Position and look of the bar. Drag widgets on the bar itself to reorder them."

  property var cfg: ({})
  FileView {
    path: Sys.home + "/.config/omarchy/shell.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { page.cfg = JSON.parse(text()) } catch (e) {} }
  }
  readonly property var bar: cfg.bar || {}
  readonly property var layout: bar.layout || {}
  // Same as nasaq.launchers' defaults, listed here while bars.launchers is unset.
  readonly property var defaultLaunchers: [
    { glyph: "󰊯", tooltip: "Browser", command: "omarchy-launch-browser" },
    { glyph: "󰉋", tooltip: "Files", command: "omarchy-launch-nautilus" },
    { svg: "assets/claude.svg", tooltip: "Claude", command: "claude", terminal: true },
    { svg: "assets/codex.svg", tooltip: "Codex", command: "codex", terminal: true }
  ]

  NSection {
    title: "BAR"
    NRow {
      title: "Position"
      NDropdown {
        model: [{ value: "top", label: "Top" }, { value: "bottom", label: "Bottom" }, { value: "left", label: "Left" }, { value: "right", label: "Right" }]
        value: page.bar.position || "top"
        onActivated: function(v) { Sys.run("omarchy bar position " + v) }
      }
    }
    NRow {
      title: "Transparent background"
      subtitle: "Same as double-clicking empty bar space."
      NSwitch { checked: !!page.bar.transparent; onToggled: function(c) { Sys.run("omarchy bar transparent " + (c ? "true" : "false")) } }
    }
    NRow {
      title: "Show the bar"
      subtitle: "SUPER + SHIFT + SPACE"
      NButton { text: "Hide / show"; onClicked: Sys.run("omarchy-toggle-bar") }
    }
  }

  NSection {
    title: "DISPLAYS"
    note: "Turn the bar off on a display to give its windows the whole screen."
    Repeater {
      model: Quickshell.screens
      delegate: NRow {
        required property var modelData
        title: "Bar on " + modelData.name
        subtitle: modelData.model || ""
        NSwitch {
          checked: Settings.get("bars.hiddenOn", []).indexOf(modelData.name) === -1
          enabledState: checked === false || Quickshell.screens.length > 1
          onToggled: function(c) {
            var l = Settings.get("bars.hiddenOn", []).filter(function(n) { return n !== modelData.name })
            if (!c) l.push(modelData.name)
            Settings.set("bars.hiddenOn", l)
          }
        }
      }
    }
  }

  NSection {
    title: "LAUNCHERS"
    note: "The app buttons on the left of the bar. Removing them all brings back the four defaults."
    LauncherList {
      key: "bars.launchers"
      fallback: page.defaultLaunchers
    }
    NRow {
      title: "Back to the default launchers"
      visible: Array.isArray(Settings.get("bars.launchers", null)) && Settings.get("bars.launchers", []).length > 0
      NButton { text: "Reset"; onClicked: Settings.set("bars.launchers", null) }
    }
  }

  NSection {
    title: "EXTRA LAUNCHERS"
    note: "Added after the launchers above, so a personal button does not mean listing the defaults again."
    LauncherList { key: "bars.extraLaunchers" }
  }

  NSection {
    title: "WIDGETS ON THE BAR"
    note: "Turn widgets on or off from the Plugins page."
    Repeater {
      model: ["left", "center", "right"]
      delegate: NRow {
        required property string modelData
        title: modelData.charAt(0).toUpperCase() + modelData.slice(1)
        NSub {
          width: 420
          horizontalAlignment: Text.AlignRight
          text: (page.layout[modelData] || []).map(function(w) { return w.id }).join("  ·  ")
        }
      }
    }
  }
}
