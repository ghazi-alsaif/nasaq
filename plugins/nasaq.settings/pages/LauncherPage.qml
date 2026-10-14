import QtQuick
import Quickshell
import Quickshell.Io
import "../../nasaq.commons"
import ".."

NPage {
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
    NRow { title: "Most used apps first"; subtitle: "Apps you open often and recently rank higher. Forget the history to start fresh."
      NButton { text: "Forget"; danger: true; onClicked: Sys.run("printf '{\"usage\":{}}\\n' > ~/.local/state/nasaq/spotlight.json") } }
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
