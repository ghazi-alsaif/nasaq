import QtQuick
import qs.Ui
import qs.Commons
import "../nasaq.commons" as Nasaq

BarWidget {
  id: root
  moduleName: "nasaq.launchers"

  // Every icon is painted white rather than in the bar foreground or the
  // brand colours, so the row reads as one quiet set. Glyphs are Nerd Font
  // icons; Claude and Codex use their logos recoloured white in assets/.
  // The list lives in NASAQ settings (bars.launchers):
  //   { glyph | svg, tooltip, command, rightCommand?, terminal? }
  // `terminal: true` opens the command in the default terminal.
  readonly property color iconColor: "#ffffff"
  readonly property var defaults: [
    { glyph: "󰊯", tooltip: "Browser", command: "omarchy-launch-browser" },
    { glyph: "󰉋", tooltip: "Files", command: "omarchy-launch-nautilus" },
    { svg: "assets/claude.svg", tooltip: "Claude", command: "claude", terminal: true },
    { svg: "assets/codex.svg", tooltip: "Codex", command: "codex", terminal: true }
  ]

  function terminal(title, command) {
    var appId = "org.nasaq." + String(title).toLowerCase().replace(/[^a-z0-9]+/g, "-")
    return "setsid uwsm-app -- xdg-terminal-exec --app-id=" + appId
      + " --title=" + Util.shellQuote(title) + " -e " + command
  }
  function cmd(item, command) { return item.terminal ? terminal(String(item.tooltip).split("\n")[0], command) : command }

  readonly property var launchers: {
    var l = Nasaq.Settings.get("bars.launchers", null)
    return Array.isArray(l) && l.length ? l : defaults
  }

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  Row {
    id: row
    anchors.fill: parent

    Repeater {
      model: root.launchers

      WidgetButton {
        id: button
        required property var modelData

        bar: root.bar
        text: modelData.glyph || ""
        hasVisualContent: true
        labelVisible: !modelData.svg
        foreground: root.iconColor
        fontSize: Style.bar.iconFont
        horizontalMargin: 6
        fixedWidth: modelData.svg ? Style.bar.iconSlot : -1
        tooltipText: modelData.tooltip

        onPressed: function(mouseButton) {
          if (!root.bar) return
          const m = button.modelData
          const command = mouseButton === Qt.RightButton && m.rightCommand ? m.rightCommand : m.command
          if (command) root.bar.run(root.cmd(m, command))
        }

        Image {
          visible: !!button.modelData.svg
          anchors.centerIn: parent
          width: Style.bar.iconFont
          height: Style.bar.iconFont
          fillMode: Image.PreserveAspectFit
          sourceSize.width: Math.round(width * Screen.devicePixelRatio)
          sourceSize.height: Math.round(height * Screen.devicePixelRatio)
          source: button.modelData.svg ? Qt.resolvedUrl(button.modelData.svg) : ""
        }
      }
    }
  }
}
