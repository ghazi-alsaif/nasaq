import QtQuick
import Quickshell
import Quickshell.Io
import "../../nasaq.commons"
import ".."

NPage {
  id: page
  title: Tr.t("page.widgets")
  subtitle: "Desktop widget column, Dynamic Island and prayer times."

  readonly property string islandPath: Sys.home + "/.config/omarchy/nasaq/island.json"
  property var island: ({})
  property bool hidden: false
  FileView {
    path: page.islandPath; watchChanges: true; printErrors: false
    onFileChanged: reload()
    onLoaded: { try { page.island = JSON.parse(text()) } catch (e) {} }
  }
  FileView {
    path: Sys.home + "/.local/state/nasaq/desktop-hidden"; watchChanges: true; printErrors: false
    onFileChanged: reload()
    onLoaded: page.hidden = text().trim() === "1"
    onLoadFailed: page.hidden = false
  }

  NSection {
    title: "DESKTOP"
    NRow {
      title: "Desktop widget column"
      subtitle: "Clock, prayer, weather, now playing, notes. SUPER + ALT + D"
      NSwitch { checked: !page.hidden; onToggled: function(c) { Sys.ipc("nasaq.desktop", c ? "show" : "hide"); page.hidden = !c } }
    }
  }

  Cmd { id: calStatus; script: "python3 -c 'import json,os;p=os.path.expanduser(\"~/.cache/nasaq/calendar.json\");d=json.load(open(p)) if os.path.exists(p) else {};print((\"Error: \"+d[\"error\"]) if d.get(\"error\") else (str(len(d.get(\"events\",[])))+\" events in the next 7 days\" if d.get(\"configured\") else \"No calendar connected\"))'" }
  Cmd { id: calRefresh; autoRun: false; script: "nasaq-calendar"; onDone: calStatus.refresh() }

  NSection {
    title: "CALENDAR"
    note: "Google Calendar: Settings › your calendar › Integrate calendar › “Secret address in iCal format”. The address is stored only in ~/.config/omarchy/nasaq/secrets.json (never in snapshots)."
    NRow {
      title: "iCal address"
      subtitle: calStatus.out
      Row { spacing: 8
        NTextField { id: icalField; width: 260; password: true; placeholder: "https://calendar.google.com/…/basic.ics" }
        NButton { text: "Connect"; primary: true; onClicked: {
          if (!icalField.text.trim()) return
          Sys.run("python3 -c 'import json,os,sys;p=os.path.expanduser(\"~/.config/omarchy/nasaq/secrets.json\");d=json.load(open(p)) if os.path.exists(p) else {};u=sys.argv[1];c=d.setdefault(\"calendars\",[]);c.append(u) if u not in c else None;open(p,\"w\").write(json.dumps(d,indent=2));os.chmod(p,0o600)' " + JSON.stringify(icalField.text.trim()) + " && nasaq-calendar")
          icalField.text = ""; refreshLater.restart()
        } }
      }
    }
    NRow {
      title: "Remind me before events"
      NSlider { width: 220; from: 0; to: 60; stepSize: 5; value: Settings.get("calendar.reminder", 10); valueText: Math.round(value) === 0 ? "Off" : Math.round(value) + " min"
        onMoved: function(v) { Settings.set("calendar.reminder", Math.round(v)) } }
    }
    NRow {
      title: "Calendars"
      Row { spacing: 8
        NButton { text: "Refresh"; onClicked: calRefresh.refresh() }
        NButton { text: "Disconnect all"; danger: true; onClicked: { Sys.run("python3 -c 'import json,os;p=os.path.expanduser(\"~/.config/omarchy/nasaq/secrets.json\");d=json.load(open(p)) if os.path.exists(p) else {};d[\"calendars\"]=[];open(p,\"w\").write(json.dumps(d,indent=2))' && nasaq-calendar"); refreshLater.restart() } }
      }
    }
  }
  Timer { id: refreshLater; interval: 4000; onTriggered: calStatus.refresh() }

  NSection {
    title: "SYSTEM CARD"
    note: "CPU, memory and temperatures in the widget column, refreshed every 5 seconds while it is shown."
    NRow {
      title: "Show the system card"
      NSwitch { checked: Settings.get("desktop.system", true); onToggled: function(c) { Settings.set("desktop.system", c) } }
    }
    NRow {
      title: "Warm from"
      subtitle: "Temperature turns yellow."
      NSlider { width: 220; from: 45; to: 90; stepSize: 1; value: Settings.get("temps.warn", 60); valueText: Math.round(value) + "°"
        onMoved: function(v) { Settings.set("temps.warn", Math.round(v)) } }
    }
    NRow {
      title: "Hot from"
      subtitle: "Temperature turns red."
      NSlider { width: 220; from: 60; to: 100; stepSize: 1; value: Settings.get("temps.hot", 80); valueText: Math.round(value) + "°"
        onMoved: function(v) { Settings.set("temps.hot", Math.round(v)) } }
    }
  }

  NSection {
    title: "DYNAMIC ISLAND"
    NRow {
      title: "Date in the island card"
      NDropdown {
        model: [{ value: "both", label: "Gregorian + Hijri" }, { value: "hijri", label: "Hijri only" }, { value: "gregorian", label: "Gregorian only" }]
        value: Settings.get("island.hijri", "both")
        onActivated: function(v) { Settings.set("island.hijri", v) }
      }
    }
    NRow {
      title: "Expand the island"
      NButton { text: "Toggle"; onClicked: Sys.ipc("nasaq.island", "toggle") }
    }
  }

  NSection {
    title: "POMODORO (TEST)"
    note: "Focus and break countdown in the island. Also in the Omarchy menu › NASAQ › Pomodoro."
    NRow { title: "Focus"; NSlider { width: 220; from: 10; to: 60; stepSize: 5; value: Settings.get("pomodoro.work", 25); valueText: Math.round(value) + " min"; onMoved: function(v) { Settings.set("pomodoro.work", Math.round(v)) } } }
    NRow { title: "Break"; NSlider { width: 220; from: 3; to: 15; stepSize: 1; value: Settings.get("pomodoro.break", 5); valueText: Math.round(value) + " min"; onMoved: function(v) { Settings.set("pomodoro.break", Math.round(v)) } } }
    NRow { title: "Long break (every 4th)"; NSlider { width: 220; from: 10; to: 30; stepSize: 5; value: Settings.get("pomodoro.longBreak", 15); valueText: Math.round(value) + " min"; onMoved: function(v) { Settings.set("pomodoro.longBreak", Math.round(v)) } } }
    NRow { title: "Start / stop"; NButton { text: "Toggle"; onClicked: Sys.ipc("nasaq.pomodoro", "toggle") } }
  }

  NSection {
    title: "PRAYER TIMES"
    note: "City: " + (page.island.city || "not set") + ". Change the city from the island's settings."
    NRow {
      title: "Calculation method"
      NDropdown {
        width: 260
        model: [{ value: 4, label: "Umm al-Qura, Makkah" }, { value: 3, label: "Muslim World League" }, { value: 2, label: "ISNA (North America)" },
                { value: 5, label: "Egyptian Authority" }, { value: 8, label: "Gulf Region" }, { value: 9, label: "Kuwait" }, { value: 10, label: "Qatar" }]
        value: Number(page.island.method || 4)
        onActivated: function(v) { Sys.jsonSet(page.islandPath, "method", JSON.stringify(v)) }
      }
    }
    NRow {
      title: "Remind me before each prayer"
      NSlider {
        width: 220
        from: 0; to: 30; stepSize: 1
        value: Number(page.island.reminderMinutes === undefined ? 5 : page.island.reminderMinutes)
        valueText: Math.round(value) === 0 ? "Off" : Math.round(value) + " min"
        onMoved: function(v) { var c = Object.assign({}, page.island); c.reminderMinutes = v; page.island = c }
        onCommitted: function(v) { Sys.jsonSet(page.islandPath, "reminderMinutes", String(Math.round(v))) }
      }
    }
  }
}
