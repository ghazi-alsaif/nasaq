import QtQuick
import Quickshell
import Quickshell.Io
import "../../nasaq.commons"
import ".."

NPage {
  id: page
  title: Tr.t("page.appearance")
  subtitle: "Theme, background, night light and screensaver."

  function slug(s) { return String(s).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") }

  Cmd { id: themes; script: "{ ls -1 \"${OMARCHY_PATH:-/usr/share/omarchy}/themes\"; ls -1 \"$HOME/.config/omarchy/themes\"; } 2>/dev/null | sort -u" }
  Cmd { id: current; script: "omarchy theme current" }
  Cmd { id: sunset; script: "hyprctl hyprsunset temperature 2>/dev/null" }
  Cmd { id: saver; script: "screensaver-mode status 2>/dev/null | head -1 | sed 's/.*: //'" }
  Cmd { id: textSize; script: "omarchy display text size 2>/dev/null | head -1 | grep -oE '[0-9]+'" }

  NSection {
    title: "THEME"
    NRow {
      title: "Omarchy theme"
      subtitle: "Applies to the shell, terminals, editors and browser."
      NDropdown {
        width: 240
        model: themes.out ? themes.out.split("\n") : []
        value: page.slug(current.out)
        onActivated: function(v) { Sys.run("omarchy theme set " + v); current.out = v }
      }
    }
    NRow {
      title: "Background"
      Row {
        spacing: 8
        NButton { text: "Next"; icon: "󰒭"; onClicked: Sys.run("omarchy-theme-bg-next") }
        NButton { text: "Choose…"; icon: "󰋩"; onClicked: Sys.run("omarchy-theme-bg-switcher") }
      }
    }
  }

  NSection {
    title: "MOTION"
    note: "How panels, the island and lists move. Power saver turns motion off by itself."
    NRow {
      title: "Motion"
      subtitle: Motion.saver ? "Off while power saver is on" : ""
      NDropdown {
        width: 200
        model: [{ value: 1, label: "Normal" }, { value: 0.5, label: "Reduced" }, { value: 0, label: "Off" }]
        value: Number(Settings.get("motion.scale", 1))
        onActivated: function(v) { Settings.set("motion.scale", v) }
      }
    }
  }

  NSection {
    title: "SCREEN FRAME (TEST)"
    note: "A rounded frame around the screen in the theme colour, inside the window gaps. Turn it on in Plugins › Screen Frame."
    NRow { title: "Thickness"; NSlider { width: 220; from: 2; to: 10; stepSize: 1; value: Settings.get("frame.thickness", 6); valueText: Math.round(value) + " px"; onMoved: function(v) { Settings.set("frame.thickness", Math.round(v)) } } }
    NRow { title: "Corner radius"; NSlider { width: 220; from: 0; to: 30; stepSize: 1; value: Settings.get("frame.radius", 18); valueText: Math.round(value) + " px"; onMoved: function(v) { Settings.set("frame.radius", Math.round(v)) } } }
    NRow { title: "Opacity"; NSlider { width: 220; from: 0.3; to: 1; stepSize: 0.05; value: Settings.get("frame.alpha", 0.9); valueText: Math.round(value * 100) + "%"; onMoved: function(v) { Settings.set("frame.alpha", v) } } }
  }

  NSection {
    title: "DISPLAY"
    NRow {
      title: "Night light"
      subtitle: sunset.out ? ("Colour temperature " + sunset.out + " K") : "hyprsunset"
      NSwitch {
        checked: Number(sunset.out) > 0 && Number(sunset.out) < 6000
        onToggled: { Sys.run("omarchy-toggle-nightlight"); refresh.restart() }
      }
    }
    NRow {
      title: "Text size"
      subtitle: "Scales text in the shell, GTK apps and terminals."
      NSlider {
        width: 220
        from: 11; to: 20; stepSize: 1
        value: Number(textSize.out) || 14
        valueText: Math.round(value) + " px"
        onMoved: function(v) { textSize.out = String(Math.round(v)) }
        onCommitted: function(v) { Sys.run("omarchy display text size " + Math.round(v)) }
      }
    }
  }

  NSection {
    title: "SCREENSAVER"
    NRow {
      title: "Style"
      NDropdown {
        model: [{ value: "matrix", label: "Matrix (green)" }, { value: "image", label: "Image" }, { value: "stock-ascii", label: "Omarchy ASCII" }]
        value: saver.out
        onActivated: function(v) { Sys.run("screensaver-mode " + v); saver.out = v }
      }
    }
    NRow {
      title: "Preview"
      NButton { text: "Show now"; onClicked: Sys.run("omarchy-launch-screensaver force") }
    }
  }

  Timer { id: refresh; interval: 700; onTriggered: sunset.refresh() }
}
