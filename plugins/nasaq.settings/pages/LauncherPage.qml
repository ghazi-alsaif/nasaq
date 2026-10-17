import QtQuick
import Quickshell
import Quickshell.Io
import "../../nasaq.commons"
import ".."

NPage {
  id: page
  title: Tr.t("page.launcher")
  subtitle: "Search and the Omarchy menu."

  NSection {
    title: "SEARCH"
    note: "Apps, files, calculator, currency, units and web search."
    NRow { title: "Open Search"; subtitle: "ALT + SPACE"; NButton { text: "Open"; onClicked: Sys.ipc("nasaq.spotlight", "open") } }
    NRow { title: "Open windows"; subtitle: "Type part of a window title to jump to it."
      NSwitch { checked: Settings.get("launcher.windows", true); onToggled: function(c) { Settings.set("launcher.windows", c) } } }
    NRow { title: "Files and folders"; subtitle: "Names under your home folder, newest first."
      NSwitch { checked: Settings.get("launcher.files", true); onToggled: function(c) { Settings.set("launcher.files", c) } } }
    NRow { title: "Ask your agent (TEST)"; subtitle: "Start with ? or ؟ to ask, e.g. “? turn on night light”. Answered by the default agent (Omarchy › Setup › Defaults). A suggested command runs only after Enter, and only from a safe list."
      NSwitch { checked: Settings.get("launcher.ai", true); onToggled: function(c) { Settings.set("launcher.ai", c) } } }
    NRow { title: "Preview"; subtitle: "Preview the selected file (images, PDF, text, folders) beside the results."
      NSwitch { checked: Settings.get("launcher.preview", true); onToggled: function(c) { Settings.set("launcher.preview", c) } } }
    NRow { title: "Web search"
      NSwitch { checked: Settings.get("launcher.web", true); onToggled: function(c) { Settings.set("launcher.web", c) } } }
    NRow { title: "Run commands"; subtitle: "Start with > to run a command, e.g. “> htop”. Enter runs it in the background, Shift+Enter in a terminal."
      NSwitch { checked: Settings.get("launcher.commands", true); onToggled: function(c) { Settings.set("launcher.commands", c) } } }
    NRow { title: "Tap SUPER alone to open Search"; subtitle: "A quick press and release of SUPER with nothing else. Needs the udev rule from the installer."
      NSwitch { checked: Settings.get("launcher.superTap", true) !== false; onToggled: function(c) { Settings.set("launcher.superTap", c) } } }
    NRow { title: "Most used apps first"; subtitle: "Apps you open often and recently rank higher. Forget the history to start fresh."
      NButton { text: "Forget"; danger: true; onClicked: Sys.run("printf '{\"usage\":{}}\\n' > ~/.local/state/nasaq/spotlight.json") } }
  }
  function appName(id) { var e = DesktopEntries.byId ? DesktopEntries.byId(id) : null; return e && e.name ? e.name : id }
  NSection {
    title: "FAVOURITE APPS"
    note: "In Search, Ctrl+D marks the selected app as a favourite (it leads the list) and Ctrl+H hides it."
    NRow { visible: { void Settings.revision; return (Settings.get("launcher.favorites", []) || []).length === 0 }; title: "No favourites yet" }
    Repeater {
      model: { void Settings.revision; return Settings.get("launcher.favorites", []) || [] }
      delegate: NRow {
        required property string modelData
        title: page.appName(modelData)
        NButton { text: "Remove"; onClicked: Settings.set("launcher.favorites", (Settings.get("launcher.favorites", []) || []).filter(function(x) { return x !== modelData })) }
      }
    }
  }
  NSection {
    title: "HIDDEN APPS"
    NRow { visible: { void Settings.revision; return (Settings.get("launcher.hidden", []) || []).length === 0 }; title: "Nothing hidden" }
    Repeater {
      model: { void Settings.revision; return Settings.get("launcher.hidden", []) || [] }
      delegate: NRow {
        required property string modelData
        title: page.appName(modelData)
        NButton { text: "Show again"; onClicked: Settings.set("launcher.hidden", (Settings.get("launcher.hidden", []) || []).filter(function(x) { return x !== modelData })) }
      }
    }
  }
  NSection {
    title: "OMARCHY MENU"
    NRow { title: "Omarchy menu"; subtitle: "SUPER + SPACE"; NButton { text: "Open"; onClicked: Sys.run("omarchy-menu toggle") } }
    NRow { title: "Apps"; subtitle: "SUPER + ALT + SPACE"; NButton { text: "Open"; onClicked: Sys.run("omarchy-menu toggle apps") } }
    NRow {
      title: "Custom menu entries"
      subtitle: "~/.config/omarchy/extensions/omarchy-menu.jsonc — reloads on save."
      NButton { text: "Edit"; onClicked: Sys.edit(Sys.home + "/.config/omarchy/extensions/omarchy-menu.jsonc") }
    }
  }
}
