import QtQuick
import Quickshell
import Quickshell.Io
import "../../nasaq.commons"
import ".."

NPage {
  id: page
  title: Tr.t("page.advanced")
  subtitle: "Files, reloads and update safety."

  Cmd {
    id: health
    script: "for u in nasaq-auto-brightness voxtype rclone-mount hermes-gateway srsd-codex-monitor; do systemctl --user cat $u >/dev/null 2>&1 && echo \"svc|$u|$(systemctl --user is-active $u)\"; done; " +
            "for c in claude tensaku-edit matugen cava nwg-displays tesseract quickshell hyprctl; do command -v $c >/dev/null && echo \"dep|$c|ok\" || echo \"dep|$c|missing\"; done; " +
            "tesseract --list-langs 2>/dev/null | grep -qx ara && echo 'dep|arabic OCR data|ok' || echo 'dep|arabic OCR data|missing'; " +
            "echo \"check|$(nasaq-clone-check 2>&1 | head -1)\"; echo \"hypr|$(hyprctl configerrors | grep -c .)\""
  }
  readonly property var lines: health.out ? health.out.split("\n") : []
  function rowsOf(kind) { return lines.filter(function(l) { return l.indexOf(kind + "|") === 0 }).map(function(l) { return l.split("|") }) }

  NSection {
    title: "HEALTH"
    note: "What NASAQ relies on, checked now."
    NRow { title: "Recheck"; NButton { text: "Refresh"; onClicked: health.refresh() } }
    NRow {
      title: "Hyprland config"
      subtitle: { var r = page.rowsOf("hypr"); return r.length && r[0][1] === "0" ? "No errors" : (r.length ? r[0][1] + " error lines — run hyprctl configerrors" : "…") }
    }
    NRow { title: "After Omarchy updates"; subtitle: { var r = page.rowsOf("check"); return r.length ? r[0][1] : "…" } }
    Repeater {
      model: page.rowsOf("svc")
      delegate: NRow { required property var modelData; title: "Service · " + modelData[1]; subtitle: modelData[2]
        NButton { text: "Restart"; onClicked: { Sys.run("systemctl --user restart " + modelData[1]); health.refresh() } } }
    }
    NRow {
      title: "Tools"
      subtitle: page.rowsOf("dep").map(function(r) { return (r[2] === "ok" ? "✓ " : "✗ ") + r[1] }).join("   ")
    }
  }

  NSection {
    title: "RELOAD"
    NRow { title: "Reload Hyprland"; NButton { text: "Reload"; onClicked: Sys.run("hyprctl reload") } }
    NRow { title: "Restart the shell"; subtitle: "Bar, island and widgets restart (about two seconds)."; NButton { text: "Restart"; danger: true; onClicked: Sys.run("omarchy restart shell") } }
  }
  NSection {
    title: "UPDATE SAFETY"
    NRow { title: "Check plugin copies against Omarchy"; subtitle: "Runs after every Omarchy update."; NButton { text: "Check now"; onClicked: Sys.term("nasaq-clone-check; read -n1 -p 'Press any key'") } }
    NRow { title: "Saved snapshots"; NButton { text: "List"; onClicked: Sys.term("nasaq-settings log; read -n1 -p 'Press any key'") } }
  }
  NSection {
    title: "FILES"
    NRow { title: "NASAQ settings file"; subtitle: "~/.config/omarchy/nasaq/settings.json"; NButton { text: "Edit"; onClicked: Sys.edit(Sys.home + "/.config/omarchy/nasaq/settings.json") } }
    NRow { title: "NASAQ folder"; NButton { text: "Open"; onClicked: Sys.run("omarchy-launch-nautilus ~/.config/omarchy/nasaq || nautilus ~/.config/omarchy/nasaq") } }
    NRow { title: "Shell log"; NButton { text: "Show"; onClicked: Sys.term("journalctl --user -t omarchy-shell -n 200 --no-pager | less") } }
  }
}
