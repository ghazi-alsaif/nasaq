import QtQuick
import Quickshell
import Quickshell.Io
import "../../nasaq.commons"
import ".."

NPage {
  id: page
  title: Tr.t("page.widgets")
  subtitle: "Desktop widget column, the island and prayer times."

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
    NRow {
      title: "Column position"
      subtitle: "Windows tile around it. With both sides, pick each card's side below."
      NDropdown {
        model: [{ value: "left", label: "Left" }, { value: "right", label: "Right" }, { value: "both", label: "Both sides" }]
        value: Settings.get("desktop.side", "left")
        onActivated: function(v) { Settings.set("desktop.side", v) }
      }
    }
  }

  NSection {
    title: "WIDGETS"
    note: "Turn each card on or off, and drag the handle to change the order, top to bottom. The column closes the gap where a card is off. Tasks & notes takes the height the other cards leave."
    Item {
      id: orderList
      width: parent.width
      height: orderModel.count * rowH
      readonly property int rowH: 54
      readonly property var defaults: ["clock", "prayer", "weather", "calendar", "system", "player", "notes"]
      readonly property var info: ({
        clock: { title: "Clock", subtitle: "Time, date and Hijri date" },
        prayer: { title: "Prayer times", subtitle: "Next prayer, countdown and the five times" },
        weather: { title: "Weather", subtitle: "Current conditions, high and low" },
        calendar: { title: "Up next", subtitle: "Events from the iCal calendars below" },
        system: { title: "System", subtitle: "CPU, memory and temperatures" },
        player: { title: "Now playing", subtitle: "Media title, art and controls" },
        notes: { title: "Tasks & notes", subtitle: "The two-tab card" }
      })
      ListModel { id: orderModel }
      Component.onCompleted: {
        var o = Settings.get("desktop.order", defaults), seen = {}
        for (var i = 0; i < o.length; i++) if (info[o[i]] && !seen[o[i]]) { seen[o[i]] = true; orderModel.append({ key: o[i] }) }
        for (var j = 0; j < defaults.length; j++) if (!seen[defaults[j]]) orderModel.append({ key: defaults[j] })
      }
      function save() {
        var keys = []
        for (var i = 0; i < orderModel.count; i++) keys.push(orderModel.get(i).key)
        Settings.set("desktop.order", keys)
      }
      Repeater {
        model: orderModel
        delegate: Item {
          id: rowItem
          required property int index
          required property string key
          width: orderList.width
          height: orderList.rowH
          y: index * orderList.rowH
          z: handleMouse.drag.active ? 2 : 1
          Behavior on y { enabled: !handleMouse.drag.active; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          Rectangle {
            anchors.fill: parent
            anchors.bottomMargin: 1
            radius: 10
            color: handleMouse.drag.active ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
          }
          NGlyph {
            id: handle
            anchors.left: parent.left
            anchors.leftMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            text: "󰇜"
            font.pixelSize: 16
            opacity: handleMouse.containsMouse || handleMouse.drag.active ? 1 : 0.45
            MouseArea {
              id: handleMouse
              anchors.fill: parent
              anchors.margins: -8
              hoverEnabled: true
              cursorShape: handleMouse.drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
              drag.target: rowItem
              drag.axis: Drag.YAxis
              drag.minimumY: 0
              drag.maximumY: (orderModel.count - 1) * orderList.rowH
              onPositionChanged: {
                if (!drag.active) return
                var to = Math.max(0, Math.min(orderModel.count - 1, Math.round(rowItem.y / orderList.rowH)))
                if (to !== rowItem.index) orderModel.move(rowItem.index, to, 1)
              }
              onReleased: { rowItem.y = rowItem.index * orderList.rowH; orderList.save() }
            }
          }
          Column {
            anchors.left: handle.right
            anchors.leftMargin: 14
            anchors.right: sideBtn.visible ? sideBtn.left : sw.left
            anchors.rightMargin: Theme.spacingLarge
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            NLabel { width: parent.width; text: Tr.s(orderList.info[rowItem.key].title); font.weight: Font.Normal }
            NSub { width: parent.width; text: Tr.s(orderList.info[rowItem.key].subtitle) }
          }
          // With two columns: which side this card sits on (same default as nasaq.desktop).
          readonly property string cardSide: {
            var c = (Settings.get("desktop.columns", {}) || {})[rowItem.key]
            return c === "left" || c === "right" ? c : (["system", "player", "notes"].indexOf(rowItem.key) >= 0 ? "right" : "left")
          }
          NButton {
            id: sideBtn
            visible: Settings.get("desktop.side", "left") === "both"
            anchors.right: sw.left
            anchors.rightMargin: Theme.spacingLarge
            anchors.verticalCenter: parent.verticalCenter
            text: rowItem.cardSide === "left" ? "󰁍  Left" : "Right  󰁔"
            onClicked: {
              var m = Object.assign({}, Settings.get("desktop.columns", {}) || {})
              m[rowItem.key] = rowItem.cardSide === "left" ? "right" : "left"
              Settings.set("desktop.columns", m)
            }
          }
          NSwitch {
            id: sw
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: Settings.get("desktop." + rowItem.key, true)
            onToggled: function(c) { Settings.set("desktop." + rowItem.key, c) }
          }
          Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.divider; opacity: 0.6 }
        }
      }
    }
  }

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
  // Calendar status and refresh (lost in 1.0.2, which left the iCal row blank
  // and Refresh doing nothing).
  Cmd { id: calStatus; script: "python3 -c 'import json,os;p=os.path.expanduser(\"~/.cache/nasaq/calendar.json\");d=json.load(open(p)) if os.path.exists(p) else {};print((\"Error: \"+d[\"error\"]) if d.get(\"error\") else (str(len(d.get(\"events\",[])))+\" events in the next 7 days\" if d.get(\"configured\") else \"No calendar connected\"))'" }
  Cmd { id: calRefresh; autoRun: false; script: "nasaq-calendar"; onDone: calStatus.refresh() }
  Timer { id: refreshLater; interval: 4000; onTriggered: calStatus.refresh() }

  NSection {
    title: "SYSTEM CARD"
    note: "CPU, memory and temperatures in the widget column, refreshed every 5 seconds while it is shown."
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
      title: "Status toasts"
      subtitle: "Caps Lock, keyboard language and charger changes, shown briefly in the island."
      NSwitch { checked: Settings.get("island.statusToasts", true); onToggled: function(c) { Settings.set("island.statusToasts", c) } }
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
      title: "Prayer times in the island"
      subtitle: "The countdown in the bar and the prayer row in the island card. The desktop prayer card has its own switch above."
      NSwitch { checked: Settings.get("island.prayer", true); onToggled: function(c) { Settings.set("island.prayer", c) } }
    }
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
