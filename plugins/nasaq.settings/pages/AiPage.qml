import QtQuick
import Quickshell
import Quickshell.Io
import "../../nasaq.commons"
import ".."

NPage {
  id: page
  title: Tr.t("page.ai")
  subtitle: "The coding agent Omarchy launches everywhere."

  Cmd { id: current; script: "omarchy-default-agent" }
  Cmd {
    id: installed
    script: "for a in claude codex opencode copilot crush cursor-agent hermes pi omp grok; do command -v $a >/dev/null && echo $a; done; command -v agy >/dev/null && echo antigravity"
  }

  NSection {
    title: "TRANSLATE AND SUMMARISE"
    note: "Select text anywhere (or copy it), then press SUPER + CTRL + ALT + L. The result appears in the island and is copied. Answered by your default agent (" + current.out + ")."
    NRow {
      title: "Translate to"
      NDropdown {
        model: [{ value: "auto", label: "Auto (Arabic ⇄ English)" }, { value: "en", label: "English" }, { value: "ar", label: "Arabic" }]
        value: Settings.get("translate.target", "auto")
        onActivated: function(v) { Settings.set("translate.target", v) }
      }
    }
    NRow {
      title: "Speed"
      subtitle: "Fast uses the agent's quickest model (Claude: Haiku). Careful uses its default."
      NDropdown {
        model: [{ value: "fast", label: "Fast" }, { value: "careful", label: "Careful" }]
        value: Settings.get("translate.model", "fast")
        onActivated: function(v) { Settings.set("translate.model", v) }
      }
    }
    NRow {
      title: "Run on the clipboard now"
      Row { spacing: 8
        NButton { text: "Translate"; onClicked: Sys.run("nasaq-translate") }
        NButton { text: "Summarise"; onClicked: Sys.run("nasaq-translate --summary") }
        NButton { text: "Screen region…"; onClicked: Sys.run("sleep 0.4; nasaq-translate --region") } }
    }
  }

  property string autoName: ""
  property string autoCmd: ""
  property string autoWhen: "daily"
  Cmd { id: autoList; script: "nasaq-auto list" }
  function applyAutos(list) { Settings.set("automations", list); autoLater.restart() }
  Timer { id: autoLater; interval: 600; onTriggered: { Sys.run("nasaq-auto apply"); autoList.refresh() } }

  NSection {
    title: "AUTOMATIONS (TEST)"
    note: "Run a command on a schedule (a systemd user timer). Missed runs happen at the next login."
    Repeater {
      model: Settings.get("automations", [])
      delegate: NRow {
        required property var modelData
        required property int index
        title: modelData.name + "  ·  " + modelData.schedule
        subtitle: modelData.command
        Row { spacing: 8
          NSwitch { anchors.verticalCenter: parent.verticalCenter; checked: modelData.enabled !== false
            onToggled: function(c) { var l = Settings.get("automations", []).slice(); l[index] = Object.assign({}, l[index], { enabled: c }); page.applyAutos(l) } }
          NButton { text: "Run now"; onClicked: Sys.run(modelData.command) }
          NButton { text: "Remove"; danger: true; onClicked: { var l = Settings.get("automations", []).slice(); l.splice(index, 1); page.applyAutos(l) } } }
      }
    }
    NRow {
      title: "New automation"
      subtitle: "Example: weekly setup export → nasaq-export-setup"
      Column { spacing: 6
        NTextField { width: 300; placeholder: "Name"; onEdited: function(t) { page.autoName = t.trim() } }
        NTextField { width: 300; placeholder: "Command"; onEdited: function(t) { page.autoCmd = t.trim() } }
        NDropdown { width: 300; value: page.autoWhen; onActivated: function(v) { page.autoWhen = v }
          model: [{ value: "hourly", label: "Every hour" }, { value: "daily", label: "Every day (midnight)" }, { value: "*-*-* 09:00", label: "Every day at 9:00" },
                  { value: "Mon *-*-* 10:00", label: "Mondays at 10:00" }, { value: "weekly", label: "Every week" }, { value: "monthly", label: "Every month" }] }
        NButton { text: "Add"; primary: true; onClicked: {
          if (!page.autoName || !page.autoCmd) return
          var l = Settings.get("automations", []).filter(function(a) { return a.name !== page.autoName })
          l.push({ name: page.autoName, command: page.autoCmd, schedule: page.autoWhen, enabled: true }); page.applyAutos(l)
        } }
      }
    }
  }

  NSection {
    title: "AGENT"
    NRow {
      title: "Default agent"
      subtitle: "Only agents installed on this machine are listed."
      NDropdown {
        model: installed.out ? installed.out.split("\n") : []
        value: current.out
        onActivated: function(v) { Sys.run("omarchy-default-agent " + v); current.out = v }
      }
    }
    NRow { title: "Start the agent"; subtitle: "SUPER + SHIFT + CTRL + A"; NButton { text: "Launch"; onClicked: Sys.run("omarchy-agent") } }
    NRow { title: "Agent usage in the bar"; subtitle: "Refresh the usage meters"; NButton { text: "Refresh"; onClicked: Sys.run("omarchy-agent-usage-update") } }
  }
}
