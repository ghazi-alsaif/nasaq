// NASAQ: macOS-style desktop widgets on the wallpaper — clock (with Hijri
// date), next prayer, weather and now playing. They live on the Bottom layer,
// so windows cover them and they show on an empty desktop.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.Commons
import "../nasaq.island/Island.js" as Island
import "../nasaq.island/Weather.js" as Weather
import "../nasaq.commons" as Nasaq

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""

  readonly property string textFont: "IBM Plex Sans Arabic"
  readonly property string iconFont: Style.font.family
  readonly property string home: Quickshell.env("HOME")
  readonly property color glass: Util.alpha(Color.background, 0.55)

  property var config: ({ city: "", latitude: 21.4225, longitude: 39.8262, method: 4 })
  property var prayerDay: null
  property var weather: null

  SystemClock { id: clock; precision: SystemClock.Seconds }
  readonly property date now: clock.date
  readonly property var nextPrayer: Island.nextPrayer(prayerDay, now)
  readonly property real msToNext: nextPrayer ? nextPrayer.time.getTime() - now.getTime() : -1

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: {
    var fallback = null
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p || !(p.trackTitle || p.trackArtist)) continue
      if (p.isPlaying) return p
      if (!fallback) fallback = p
    }
    return fallback
  }

  // ── Data ─────────────────────────────────────────────────────────
  FileView {
    path: root.home + "/.config/omarchy/nasaq/island.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.config = Object.assign({}, root.config, JSON.parse(text())) } catch (e) {}
      root.prayerDay = null
      root.refresh()
    }
  }

  function refresh() {
    var d = new Date()
    if (!prayerProc.running) {
      prayerProc.command = ["bash", "-c",
        "cache=\"${XDG_CACHE_HOME:-$HOME/.cache}/nasaq-island\"; mkdir -p \"$cache\"; " +
        "f=\"$cache/prayer-$1-$2-$3-$4-$5.json\"; " +
        "if [ ! -s \"$f\" ]; then curl -4 -sf --max-time 15 \"https://api.aladhan.com/v1/calendar/$1/$2?latitude=$3&longitude=$4&method=$5\" -o \"$f.tmp\" " +
        "&& jq -e '.code == 200' \"$f.tmp\" >/dev/null && mv \"$f.tmp\" \"$f\"; rm -f \"$f.tmp\"; fi; cat \"$f\" 2>/dev/null",
        "nasaq-prayer", String(d.getFullYear()), String(d.getMonth() + 1),
        String(config.latitude), String(config.longitude), String(config.method || 4)]
      prayerProc.running = true
    }
    if (!weatherProc.running) {
      weatherProc.command = ["bash", "-c", Weather.fetchScript, "nasaq-weather", String(config.latitude), String(config.longitude)]
      weatherProc.running = true
    }
  }

  Process {
    id: prayerProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { var p = Island.dayFromMonth(text, new Date()); if (p) root.prayerDay = p } }
  }
  Process {
    id: weatherProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { var w = Weather.parse(text); if (w) root.weather = w } }
  }

  // Midnight rollover and weather every 30 minutes.
  Timer {
    interval: 30 * 60 * 1000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }
  property string dayKey: Qt.formatDate(now, "yyyyMMdd")
  onDayKeyChanged: { prayerDay = null; refresh() }
  // Still no prayer times 20 s after asking (no network and nothing cached):
  // say so instead of silently dropping the card.
  property bool prayerMissing: false
  onPrayerDayChanged: { if (prayerDay !== null) { prayerMissing = false; prayerWait.stop() } else prayerWait.restart() }
  Timer { id: prayerWait; interval: 20000; running: true; onTriggered: root.prayerMissing = root.prayerDay === null }

  Timer {
    interval: 1000
    repeat: true
    running: root.player !== null && root.player.isPlaying
    onTriggered: if (root.player) root.player.positionChanged()
  }

  // ── System card: CPU, memory, temperatures (NASAQ Settings > Widgets) ──
  readonly property bool sysEnabled: Nasaq.Settings.get("desktop.system", true)
  // One switch per widget (Settings > Widgets); hidden cards leave no gap.
  readonly property bool clockEnabled: Nasaq.Settings.get("desktop.clock", true)
  readonly property bool prayerEnabled: Nasaq.Settings.get("desktop.prayer", true)
  readonly property bool weatherEnabled: Nasaq.Settings.get("desktop.weather", true)
  readonly property bool calendarEnabled: Nasaq.Settings.get("desktop.calendar", true)
  readonly property bool playerEnabled: Nasaq.Settings.get("desktop.player", true)
  readonly property bool notesEnabled: Nasaq.Settings.get("desktop.notes", true)
  readonly property var defaultOrder: ["clock", "prayer", "weather", "calendar", "system", "player", "notes"]
  // Top-to-bottom order of the cards (Settings > Widgets, drag the handles).
  readonly property var cardOrder: {
    var o = Nasaq.Settings.get("desktop.order", defaultOrder)
    var seen = {}, out = []
    for (var i = 0; i < o.length; i++) if (defaultOrder.indexOf(o[i]) >= 0 && !seen[o[i]]) { seen[o[i]] = true; out.push(o[i]) }
    for (var j = 0; j < defaultOrder.length; j++) if (!seen[defaultOrder[j]]) out.push(defaultOrder[j])
    return out
  }
  readonly property int tempWarn: Nasaq.Settings.get("temps.warn", 60)
  readonly property int tempHot: Nasaq.Settings.get("temps.hot", 80)
  property var sys: null
  function tempColor(t) { return t >= tempHot ? "#ff453a" : t >= tempWarn ? "#ffd60a" : Qt.rgba(1, 1, 1, 0.9) }
  Process {
    id: sysProc
    command: ["bash", "-c",
      "read -r _ a b c d e f g h _ < /proc/stat; t1=$((a+b+c+d+e+f+g+h)); i1=$((d+e)); sleep 0.5; " +
      "read -r _ a b c d e f g h _ < /proc/stat; t2=$((a+b+c+d+e+f+g+h)); i2=$((d+e)); " +
      "cpu=$(( (100*((t2-t1)-(i2-i1)))/((t2-t1)>0?(t2-t1):1) )); " +
      "mt=$(awk '/MemTotal/{print $2}' /proc/meminfo); ma=$(awk '/MemAvailable/{print $2}' /proc/meminfo); " +
      "ct=0; gt=0; for h in /sys/class/hwmon/hwmon*; do n=$(cat $h/name 2>/dev/null); " +
      "case $n in coretemp|k10temp|zenpower) for f in $h/temp*_input; do v=$(( $(cat $f)/1000 )); [ $v -gt $ct ] && ct=$v; done;; " +
      "amdgpu|radeon|nouveau) [ -r $h/temp1_input ] && gt=$(( $(cat $h/temp1_input)/1000 ));; esac; done; " +
      // NVIDIA's own driver has no hwmon entry. Ask nvidia-smi, but only while
      // the card is already awake, so the poll never wakes a sleeping laptop GPU.
      "if [ $gt -eq 0 ] && command -v nvidia-smi >/dev/null; then for d in /sys/bus/pci/devices/*; do " +
      "[ \"$(cat $d/vendor)\" = 0x10de ] && case $(cat $d/class) in 0x03*) " +
      "[ \"$(cat $d/power/runtime_status 2>/dev/null)\" = suspended ] || gt=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1);; esac; done; gt=${gt:-0}; fi; " +
      "printf '{\"cpu\":%d,\"mem\":%d,\"cpuTemp\":%d,\"gpuTemp\":%d}\\n' $cpu $(( 100*(mt-ma)/mt )) $ct $gt"]
    stdout: StdioCollector { onStreamFinished: { try { root.sys = JSON.parse(this.text) } catch (e) {} } }
  }
  Timer { interval: 5000; repeat: true; triggeredOnStart: true; running: root.sysEnabled && !root.hidden; onTriggered: if (!sysProc.running) sysProc.running = true }

  // ── Calendar (iCal feeds; NASAQ Settings > Widgets) ─────────────
  property var calendar: ({ configured: false, events: [] })
  property var calAlerted: ({})
  readonly property int calReminder: Nasaq.Settings.get("calendar.reminder", 10)
  readonly property var upNext: {
    var now = Date.now(), out = []
    var evs = calendar.events || []
    for (var i = 0; i < evs.length && out.length < 3; i++) {
      var e = evs[i]
      var end = Date.parse(e.end)
      if ((e.allDay ? end : end) > now && e.startMs < now + 36 * 3600 * 1000) out.push(e)
    }
    return out
  }
  function calWhen(e) {
    var d = new Date(e.startMs), today = new Date()
    var tomorrow = new Date(); tomorrow.setDate(today.getDate() + 1)
    var day = d.toDateString() === today.toDateString() ? "" : d.toDateString() === tomorrow.toDateString() ? "Tomorrow " : Qt.formatDate(d, "ddd ")
    return e.allDay ? (day || "Today") + " · all day" : day + Qt.formatTime(d, "h:mm AP")
  }
  FileView {
    path: root.home + "/.cache/nasaq/calendar.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.calendar = JSON.parse(text()) } catch (e) {} }
  }
  Process { id: calProc; command: ["nasaq-calendar"] }
  Timer { interval: 15 * 60 * 1000; repeat: true; running: true; triggeredOnStart: true; onTriggered: if (!calProc.running) calProc.running = true }
  Timer {
    interval: 30000; repeat: true; running: (root.calendar.events || []).length > 0
    onTriggered: {
      var now = Date.now(), evs = root.calendar.events || []
      for (var i = 0; i < evs.length; i++) {
        var e = evs[i], key = e.title + e.startMs, left = e.startMs - now
        if (e.allDay || root.calAlerted[key] || left < 0 || left > root.calReminder * 60000) continue
        var m = Object.assign({}, root.calAlerted); m[key] = true; root.calAlerted = m
        Quickshell.execDetached(["omarchy-shell", "-q", "nasaq.island", "alert", e.title,
          "In " + Math.max(1, Math.round(left / 60000)) + " min" + (e.location ? " · " + e.location : "")])
      }
    }
  }

  // ── Live waveform (cava, only while something plays) ─────────────
  readonly property bool playing: player !== null && player.isPlaying
  property var bars: []
  Process {
    // No waveform to draw while the column is hidden.
    running: root.playing && !root.hidden
    command: ["bash", "-c",
      "cfg=$(mktemp); trap 'rm -f \"$cfg\"' EXIT; " +
      "printf '[general]\\nbars = 28\\nframerate = 30\\nsleep_timer = 1\\n[input]\\nmethod = pipewire\\n[output]\\nmethod = raw\\nraw_target = /dev/stdout\\ndata_format = ascii\\nascii_max_range = 100\\nbar_delimiter = 59\\nframe_delimiter = 10\\n[smoothing]\\nnoise_reduction = 60\\n' > \"$cfg\"; " +
      "cava -p \"$cfg\""]
    stdout: SplitParser {
      onRead: function(line) {
        var parts = String(line).split(";")
        var next = []
        for (var i = 0; i < 28; i++) next.push(parseInt(parts[i]) || 0)
        root.bars = next
      }
    }
    onRunningChanged: if (!running) root.bars = []
  }

  // ── Notes & tasks, kept in ~/.local/share/nasaq/notes.json ───────
  property string noteText: ""
  property var tasks: []
  property string notesTab: "tasks"   // NASAQ: always start on Tasks
  // Never write before the file has been read, or startup could save the
  // empty defaults over the user's notes.
  property bool notesLoaded: false
  FileView {
    id: notesFile
    path: root.home + "/.local/share/nasaq/notes.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var d = JSON.parse(text())
        root.noteText = d.note || ""
        root.tasks = Array.isArray(d.tasks) ? d.tasks : []
        root.notesTab = "tasks"
      } catch (e) {}
      root.notesLoaded = true
    }
    onLoadFailed: function(err) {
      // Only a missing file is safe to start fresh on.
      if (err === FileViewError.FileNotFound) root.notesLoaded = true
    }
  }
  function saveNotesSoon() { if (notesLoaded) notesSave.restart() }

  // Tasks stay ordered: open ones first, completed ones sink to the bottom.
  property int editingTask: -1
  function toggleTask(i) {
    var list = tasks.slice()
    var t = list.splice(i, 1)[0]
    t = { text: t.text, done: !t.done }
    if (t.done) list.push(t)
    else {
      var firstDone = list.findIndex(function(x) { return x.done })
      list.splice(firstDone < 0 ? list.length : firstDone, 0, t)
    }
    editingTask = -1
    tasks = list
    saveNotesSoon()
  }
  function renameTask(i, text) {
    var v = String(text || "").trim()
    editingTask = -1
    if (!v || !tasks[i] || tasks[i].text === v) return
    var list = tasks.slice()
    list[i] = { text: v, done: list[i].done }
    tasks = list
    saveNotesSoon()
  }
  function deleteTask(i) {
    var list = tasks.slice()
    list.splice(i, 1)
    editingTask = -1
    tasks = list
    saveNotesSoon()
  }
  Timer {
    id: notesSave
    interval: 600
    onTriggered: if (root.notesLoaded) notesFile.setText(JSON.stringify({ note: root.noteText, tasks: root.tasks, tab: root.notesTab }, null, 1) + "\n")
  }

  // ── Keep tiled windows clear of the widget column ────────────────
  // The column sits 10 px from the screen edge and 10 px from the windows,
  // the same 10 as Hyprland's gaps_out. The left window gap is written to
  // ~/.config/hypr/nasaq-desktop.lua (loaded by looknfeel.lua), so it is
  // already right at boot and survives every `hyprctl reload` without the
  // windows jumping; `hyprctl eval` applies a change at once.
  readonly property int edge: 10
  function stripFor(screenHeight) {
    var ui = Math.max(0.9, Math.min(1.45, screenHeight / 1080))
    return edge + Math.round(320 * ui)
  }
  // Hidden column (omarchy-shell nasaq.desktop toggle): windows get the space.
  property bool hidden: false
  FileView {
    id: hiddenFile
    path: root.home + "/.local/state/nasaq/desktop-hidden"
    blockLoading: true
    printErrors: false
    onLoaded: root.hidden = String(text()).trim() === "1"
  }
  function setHidden(h) {
    hidden = h
    hiddenFile.setText(h ? "1\n" : "0\n")
    syncGap()
  }
  IpcHandler {
    target: "nasaq.desktop"
    function toggle(): string { root.setHidden(!root.hidden); return root.hidden ? "hidden" : "shown" }
    function show(): string { root.setHidden(false); return "shown" }
    function hide(): string { root.setHidden(true); return "hidden" }
  }
  FileView {
    id: gapFile
    path: root.home + "/.config/hypr/nasaq-desktop.lua"
    blockLoading: false
    printErrors: false
  }
  property string lastGapLua: ""
  function syncGap() { gapTimer.restart() }
  Timer {
    id: gapTimer
    interval: 300
    onTriggered: {
      var widest = 0
      var screens = Quickshell.screens
      for (var i = 0; i < screens.length; i++) widest = Math.max(widest, root.stripFor(screens[i].height))
      if (widest <= 0) return
      var left = root.hidden ? root.edge : widest + root.edge
      var lua = "hl.config({ general = { gaps_out = { top = 10, right = 10, bottom = 10, left = " + left + " } } })"
      if (lua === root.lastGapLua) return
      root.lastGapLua = lua
      gapFile.setText("-- Generated by nasaq.desktop: room for the desktop widget column.\n" + lua + "\n")
      Quickshell.execDetached(["hyprctl", "eval", lua])
    }
  }
  // Where tiled windows start on each monitor: the bar's reserved strip plus
  // the top window gap. The widget column's top edge lines up with it.
  property var windowTop: ({})
  Process {
    id: windowTopProc
    command: ["bash", "-c", "hyprctl monitors -j | jq -c 'map({(.name): .reserved[1]}) | add'; hyprctl getoption general:gaps_out -j | jq -r '.css'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        try {
          var reserved = JSON.parse(lines[0]) || {}
          var gapTop = parseInt(String(lines[1] || "10").split(" ")[0]) || 0
          var next = {}
          for (var k in reserved) next[k] = reserved[k] + gapTop
          root.windowTop = next
        } catch (e) {}
      }
    }
  }
  Timer { id: windowTopTimer; interval: 900; onTriggered: if (!windowTopProc.running) windowTopProc.running = true }
  Component.onCompleted: windowTopTimer.restart()

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      // A reload re-reads nasaq-desktop.lua, so the gap is already right;
      // only the top edge is measured again.
      if (!event) return
      if (event.name === "monitoradded" || event.name === "monitorremoved") { root.lastGapLua = ""; root.syncGap() }
      if (event.name === "configreloaded" || event.name === "monitoradded" || event.name === "monitorremoved") windowTopTimer.restart()
    }
  }

  // ── UI ───────────────────────────────────────────────────────────
  component Card: Rectangle {
    property string key: ""
    width: 320
    radius: 26
    color: root.glass
    border.color: Qt.rgba(1, 1, 1, 0.10)
    border.width: 1
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      // A full-height strip on the left that reserves its width (like the
      // bar does at the top), so tiled windows never cover the widgets.
      // Fullscreen windows still cover everything.
      anchors { top: true; bottom: true; left: true }
      // Adapts to the screen: widgets are designed at 1080 px tall and scale
      // with the logical screen height (0.9×–1.45×), so a tall iMac screen
      // gets proportionally larger widgets and the laptop keeps 1×.
      readonly property real ui: Math.max(0.9, Math.min(1.45, (modelData ? modelData.height : 1080) / 1080))
      readonly property int stripWidth: root.stripFor(modelData ? modelData.height : 1080)
      visible: !root.hidden
      implicitWidth: stripWidth
      onStripWidthChanged: root.syncGap()
      Component.onCompleted: root.syncGap()
      color: "transparent"
      // The space is reserved for windows by a Hyprland monitor rule (see
      // monitors.lua), not by this surface — an exclusive zone here would
      // also squeeze the floating bar.
      exclusionMode: ExclusionMode.Ignore
      mask: Region { x: widgets.x; y: widgets.y; width: widgets.width * win.ui; height: widgets.implicitHeight * win.ui }
      WlrLayershell.namespace: "nasaq-desktop-widgets"
      WlrLayershell.layer: WlrLayer.Bottom
      // OnDemand so the note and task fields can take typing when clicked.
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

      Item {
        id: widgets
        x: root.edge
        // Top edge level with the tiled windows' top edge (fallback until measured).
        y: root.windowTop[win.modelData ? win.modelData.name : ""] !== undefined
           ? root.windowTop[win.modelData.name]
           : Style.bar.sizeHorizontal + Math.round(34 * win.ui)
        width: 320
        // 10 px between widgets on screen, the same as between windows
        // (the column is scaled by win.ui, so divide it back out).
        readonly property real spacing: 10 / win.ui
        scale: win.ui
        transformOrigin: Item.TopLeft
        // Cards are placed by hand in root.cardOrder; hidden cards leave no gap.
        property string lastKey: ""
        implicitHeight: 0
        function cardFor(key) { for (var i = 0; i < children.length; i++) if (children[i].key === key) return children[i]; return null }
        function relayout() {
          var y = 0, last = ""
          for (var i = 0; i < root.cardOrder.length; i++) {
            var cards = root.cardOrder[i] === "prayer" ? [cardFor("prayer"), cardFor("prayer-missing")] : [cardFor(root.cardOrder[i])]
            for (var k = 0; k < cards.length; k++) {
              var c = cards[k]
              if (!c || !c.visible) continue
              c.y = y; y += c.height + spacing; last = root.cardOrder[i]
            }
          }
          lastKey = last
          implicitHeight = Math.max(0, y - spacing)
        }
        Component.onCompleted: {
          for (var i = 0; i < children.length; i++) {
            children[i].visibleChanged.connect(relayout)
            children[i].heightChanged.connect(relayout)
          }
          relayout()
        }
        Connections { target: root; function onCardOrderChanged() { widgets.relayout() } }
        onSpacingChanged: relayout()

        // ── Clock ──
        Card {
          key: "clock"
          height: 150
          visible: root.clockEnabled
          Column {
            anchors.centerIn: parent
            spacing: -6
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: Qt.locale("en_US").toString(root.now, "h:mm AP").replace(/\s*[AP]M$/i, "")
              color: "white"
              font.family: root.textFont
              font.weight: Font.Bold
              font.pixelSize: 64
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: Qt.locale("en_US").toString(root.now, "dddd, d MMMM")
              color: Qt.rgba(1, 1, 1, 0.8)
              font.family: root.textFont
              font.weight: Font.DemiBold
              font.pixelSize: 15
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              topPadding: 4
              visible: root.prayerDay !== null
              text: root.prayerDay ? root.prayerDay.hijri.day + " " + root.prayerDay.hijri.month + " " + root.prayerDay.hijri.year + " هـ" : ""
              color: Qt.rgba(1, 1, 1, 0.8)
              font.family: root.textFont
              font.weight: Font.DemiBold
              font.pixelSize: 15
            }
          }
        }

        // ── Prayer times unavailable ──
        Card {
          key: "prayer-missing"
          height: 64
          visible: root.prayerEnabled && root.prayerMissing
          Text {
            anchors.centerIn: parent
            width: parent.width - 36
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "Prayer times unavailable. Check the internet connection."
            color: Qt.rgba(1, 1, 1, 0.7)
            font.family: root.textFont
            font.pixelSize: 13
          }
        }

        // ── Next prayer ──
        Card {
          key: "prayer"
          height: 132
          visible: root.prayerEnabled && root.prayerDay !== null && root.nextPrayer !== null
          Item {
            anchors.fill: parent
            anchors.margins: 18
            Column {
              anchors.right: parent.right
              anchors.top: parent.top
              Text {
                anchors.right: parent.right
                text: root.nextPrayer ? "صلاة " + root.nextPrayer.name : ""
                color: Color.accent
                font.family: root.textFont
                font.weight: Font.Bold
                font.pixelSize: 18
              }
              Text {
                anchors.right: parent.right
                text: root.nextPrayer ? "in " + Island.formatCountdown(root.msToNext) + " · " + Island.formatTime(root.nextPrayer.time) : ""
                color: Qt.rgba(1, 1, 1, 0.7)
                font.family: root.textFont
                font.pixelSize: 13
              }
            }
            Text {
              anchors.left: parent.left
              anchors.top: parent.top
              text: "󰽥"
              color: Color.accent
              font.family: root.iconFont
              font.pixelSize: 28
            }
            Row {
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              layoutDirection: Qt.RightToLeft
              Repeater {
                model: root.prayerDay ? root.prayerDay.prayers : []
                delegate: Column {
                  required property var modelData
                  required property int index
                  readonly property bool isNext: root.nextPrayer !== null && root.nextPrayer.index === index
                  width: parent.width / 5
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.name
                    color: isNext ? Color.accent : Qt.rgba(1, 1, 1, 0.55)
                    font.family: root.textFont
                    font.pixelSize: 11
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Island.formatTime(modelData.time)
                    color: "white"
                    font.family: root.textFont
                    font.weight: isNext ? Font.Bold : Font.Normal
                    font.pixelSize: 13
                  }
                }
              }
            }
          }
        }

        // ── Weather ──
        Card {
          key: "weather"
          height: 132
          visible: root.weatherEnabled && root.weather !== null
          Item {
            anchors.fill: parent
            anchors.margins: 18
            Column {
              anchors.left: parent.left
              anchors.top: parent.top
              Text {
                text: root.config.city || ""
                color: "white"
                font.family: root.textFont
                font.weight: Font.DemiBold
                font.pixelSize: 15
              }
              Text {
                text: root.weather ? root.weather.temp + "°" : ""
                color: "white"
                font.family: root.textFont
                font.weight: Font.Light
                font.pixelSize: 44
              }
            }
            Column {
              anchors.right: parent.right
              anchors.top: parent.top
              Text {
                anchors.right: parent.right
                text: root.weather ? root.weather.icon : ""
                color: Color.accent
                font.family: root.iconFont
                font.pixelSize: 30
              }
              Text {
                anchors.right: parent.right
                text: root.weather ? root.weather.label : ""
                color: Qt.rgba(1, 1, 1, 0.75)
                font.family: root.textFont
                font.pixelSize: 13
              }
              Text {
                anchors.right: parent.right
                text: root.weather && root.weather.days.length > 0 ? "↑" + root.weather.days[0].max + "°  ↓" + root.weather.days[0].min + "°" : ""
                color: Qt.rgba(1, 1, 1, 0.6)
                font.family: root.textFont
                font.pixelSize: 12
              }
            }
          }
        }

        // ── Up next (calendar) ──
        Card {
          key: "calendar"
          height: calCol.implicitHeight + 32
          visible: root.calendarEnabled && root.calendar.configured && root.upNext.length > 0
          Column {
            id: calCol
            x: 20; y: 16
            width: parent.width - 40
            spacing: 8
            Text { text: "Up Next"; color: Color.accent; font.family: root.textFont; font.weight: Font.DemiBold; font.pixelSize: 13 }
            Repeater {
              model: root.upNext
              delegate: Column {
                required property var modelData
                width: calCol.width
                spacing: 1
                Text { width: parent.width; text: modelData.title; color: "white"; elide: Text.ElideRight; font.family: root.textFont; font.weight: Font.DemiBold; font.pixelSize: 15 }
                Text { width: parent.width; text: root.calWhen(modelData) + (modelData.location ? "  ·  " + modelData.location : ""); color: Qt.rgba(1, 1, 1, 0.6); elide: Text.ElideRight; font.family: root.textFont; font.pixelSize: 12 }
              }
            }
          }
        }

        // ── System ──
        Card {
          key: "system"
          height: 96
          visible: root.sysEnabled && root.sys !== null
          Row {
            anchors.centerIn: parent
            spacing: 26
            Repeater {
              model: root.sys ? [
                { label: "CPU", value: root.sys.cpu + "%", color: Qt.rgba(1, 1, 1, 0.9) },
                { label: "Memory", value: root.sys.mem + "%", color: Qt.rgba(1, 1, 1, 0.9) },
                { label: "CPU °C", value: root.sys.cpuTemp > 0 ? root.sys.cpuTemp + "°" : "—", color: root.tempColor(root.sys.cpuTemp) },
                { label: "GPU °C", value: root.sys.gpuTemp > 0 ? root.sys.gpuTemp + "°" : "—", color: root.tempColor(root.sys.gpuTemp) }
              ] : []
              delegate: Column {
                required property var modelData
                spacing: 2
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.value; color: modelData.color; font.family: root.textFont; font.pixelSize: 22; font.weight: Font.DemiBold; font.features: ({ "tnum": 1 }) }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: Qt.rgba(1, 1, 1, 0.55); font.family: root.textFont; font.pixelSize: 11 }
              }
            }
          }
        }

        // ── Now playing: art, title, controls, progress, live waveform ──
        Card {
          // With nothing playing it rests as "Not Playing".
          key: "player"
          height: 178
          visible: root.playerEnabled
          Rectangle {
            id: art
            x: 16
            y: 16
            width: 64
            height: 64
            radius: 14
            color: "#1c1c1e"
            clip: true
            Image {
              anchors.fill: parent
              source: root.player && root.player.trackArtUrl ? root.player.trackArtUrl : ""
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
            }
            Text {
              anchors.centerIn: parent
              visible: !root.player || !root.player.trackArtUrl
              text: "󰝚"
              color: Color.accent
              font.family: root.iconFont
              font.pixelSize: 26
            }
          }
          Column {
            anchors.left: art.right
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.top: art.top
            spacing: 2
            Text {
              width: parent.width
              text: root.player ? (root.player.trackTitle || "") : "Not Playing"
              color: root.player ? "white" : Qt.rgba(1, 1, 1, 0.75)
              elide: Text.ElideRight
              font.family: root.textFont
              font.weight: Font.Bold
              font.pixelSize: 14
            }
            Text {
              width: parent.width
              text: root.player ? (root.player.trackArtist || root.player.identity || "") : "Music & video show up here"
              color: Qt.rgba(1, 1, 1, root.player ? 0.6 : 0.45)
              elide: Text.ElideRight
              font.family: root.textFont
              font.pixelSize: 12
            }
            Row {
              spacing: 22
              topPadding: 4
              opacity: root.player ? 1 : 0.3
              enabled: root.player !== null
              Repeater {
                model: [
                  { icon: "󰒮", act: "prev" },
                  { icon: root.player && root.player.isPlaying ? "󰏤" : "󰐊", act: "toggle" },
                  { icon: "󰒭", act: "next" }
                ]
                delegate: Text {
                  required property var modelData
                  text: modelData.icon
                  color: ctl.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.8)
                  font.family: root.iconFont
                  font.pixelSize: 18
                  MouseArea {
                    id: ctl
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (!root.player) return
                      if (modelData.act === "prev") root.player.previous()
                      else if (modelData.act === "next") root.player.next()
                      else root.player.togglePlaying()
                    }
                  }
                }
              }
            }
          }

          // Progress
          Item {
            id: progress
            x: 16
            y: 92
            width: parent.width - 32
            height: 14
            opacity: !!root.player && root.player.length > 0 ? 1 : 0.35
            readonly property real frac: root.player && root.player.length > 0 ? Math.min(1, root.player.position / root.player.length) : 0
            Text {
              id: posText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: 34
              text: root.player && root.player.length > 0 ? Island.formatMediaTime(root.player.position) : "0:00"
              color: Qt.rgba(1, 1, 1, 0.55)
              font.family: root.textFont
              font.pixelSize: 10
            }
            Rectangle {
              anchors.left: posText.right
              anchors.right: lenText.left
              anchors.rightMargin: 6
              anchors.verticalCenter: parent.verticalCenter
              height: 4
              radius: 2
              color: Qt.rgba(1, 1, 1, 0.2)
              Rectangle { width: parent.width * progress.frac; height: parent.height; radius: 2; color: "white" }
              MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                enabled: !!root.player && root.player.canSeek
                cursorShape: Qt.PointingHandCursor
                onClicked: function(m) { root.player.position = root.player.length * Math.max(0, Math.min(1, (m.x - 6) / (width - 12))) }
              }
            }
            Text {
              id: lenText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.player && root.player.length > 0 ? "-" + Island.formatMediaTime(root.player.length - root.player.position) : "--:--"
              color: Qt.rgba(1, 1, 1, 0.55)
              font.family: root.textFont
              font.pixelSize: 10
            }
          }

          // Live waveform (cava), flat bars in the theme accent.
          Row {
            x: 16
            y: 116
            width: parent.width - 32
            height: 46
            spacing: 3
            Repeater {
              model: 28
              delegate: Rectangle {
                required property int index
                width: (parent.width - 27 * 3) / 28
                anchors.bottom: parent.bottom
                radius: 1.5
                height: root.playing ? Math.max(3, 46 * (root.bars[index] || 0) / 100) : 3
                color: Color.accent
                opacity: root.playing ? 0.55 + 0.45 * Math.min(1, (root.bars[index] || 0) / 60) : 0
                Behavior on height { NumberAnimation { duration: 60 } }
              }
            }
          }
        }

        // ── Notes & Tasks (two tabs) ──
        Card {
          id: notesCard
          key: "notes"
          visible: root.notesEnabled
          // As the last card it stretches to the bottom of the screen, ending
          // at the same 10 px gap as the windows (widgets are scaled by
          // win.ui). Anywhere else it keeps a fixed height and scrolls inside.
          height: widgets.lastKey === "notes" ? Math.max(220, (win.height - 10 - widgets.y) / win.ui - y) : 300
          Row {
            id: tabs
            x: 14
            y: 14
            spacing: 6
            Repeater {
              model: [{ key: "tasks", icon: "󰄲", title: "Tasks" }, { key: "notes", icon: "󰎚", title: "Notes" }]
              delegate: Rectangle {
                required property var modelData
                readonly property bool active: root.notesTab === modelData.key
                width: tabRow.implicitWidth + 22
                height: 28
                radius: 14
                color: active ? Color.accent : Qt.rgba(1, 1, 1, tabMouse.containsMouse ? 0.14 : 0.07)
                Behavior on color { ColorAnimation { duration: 140 } }
                Row {
                  id: tabRow
                  anchors.centerIn: parent
                  spacing: 6
                  Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.icon; color: "white"; font.family: root.iconFont; font.pixelSize: 13 }
                  Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.title; color: "white"; font.family: root.textFont; font.weight: Font.DemiBold; font.pixelSize: 12 }
                }
                MouseArea {
                  id: tabMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { root.notesTab = modelData.key; root.saveNotesSoon() }
                }
              }
            }
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: tabs.verticalCenter
            visible: root.notesTab === "tasks" && root.tasks.length > 0
            text: root.tasks.filter(function(t) { return t.done }).length + "/" + root.tasks.length
            color: Qt.rgba(1, 1, 1, 0.5)
            font.family: root.textFont
            font.pixelSize: 12
          }

          // Notes tab
          Flickable {
            id: noteFlick
            visible: root.notesTab === "notes"
            x: 16
            y: 54
            width: parent.width - 32
            height: parent.height - 70
            contentHeight: noteEdit.paintedHeight + 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            TextEdit {
              id: noteEdit
              width: noteFlick.width
              text: root.noteText
              color: "white"
              selectionColor: Qt.rgba(1, 1, 1, 0.3)
              wrapMode: TextEdit.Wrap
              font.family: root.textFont
              font.pixelSize: 14
              onTextChanged: if (text !== root.noteText) { root.noteText = text; root.saveNotesSoon() }
              onCursorRectangleChanged: {
                if (cursorRectangle.y + cursorRectangle.height > noteFlick.contentY + noteFlick.height)
                  noteFlick.contentY = cursorRectangle.y + cursorRectangle.height - noteFlick.height
                else if (cursorRectangle.y < noteFlick.contentY) noteFlick.contentY = cursorRectangle.y
              }
            }
            Text {
              visible: noteEdit.text.length === 0 && !noteEdit.activeFocus
              text: "Write a note…"
              color: Qt.rgba(1, 1, 1, 0.35)
              font.family: root.textFont
              font.pixelSize: 14
            }
            MouseArea {
              anchors.fill: parent
              visible: !noteEdit.activeFocus
              cursorShape: Qt.IBeamCursor
              onClicked: noteEdit.forceActiveFocus()
            }
          }

          // Tasks tab
          Column {
            visible: root.notesTab === "tasks"
            x: 16
            y: 54
            width: parent.width - 32
            spacing: 6

            Rectangle {
              width: parent.width
              height: 32
              radius: 10
              color: Qt.rgba(1, 1, 1, 0.08)
              Text {
                id: plus
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "󰐕"
                color: Color.accent
                font.family: root.iconFont
                font.pixelSize: 14
              }
              TextInput {
                id: taskInput
                anchors.left: plus.right
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                color: "white"
                font.family: root.textFont
                font.pixelSize: 13
                clip: true
                onAccepted: {
                  var t = text.trim()
                  if (!t) return
                  var list = root.tasks.slice()
                  var firstDone = list.findIndex(function(x) { return x.done })
                  list.splice(firstDone < 0 ? list.length : firstDone, 0, { text: t, done: false })
                  root.tasks = list
                  text = ""
                  root.saveNotesSoon()
                }
                Text {
                  anchors.fill: parent
                  verticalAlignment: Text.AlignVCenter
                  visible: taskInput.text.length === 0
                  text: "Add a task…"
                  color: Qt.rgba(1, 1, 1, 0.35)
                  font: taskInput.font
                }
              }
            }

            Flickable {
              width: parent.width
              height: notesCard.height - 54 - 32 - 6 - 40
              contentHeight: taskCol.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              Column {
                id: taskCol
                width: parent.width
                spacing: 2
                Repeater {
                  model: root.tasks
                  delegate: Rectangle {
                    id: taskRow
                    required property var modelData
                    required property int index
                    readonly property bool editing: root.editingTask === index
                    readonly property bool hot: rowMouse.containsMouse || editMouse.containsMouse || delMouse.containsMouse
                    width: taskCol.width
                    height: Math.max(30, (editing ? 22 : taskText.implicitHeight) + 10)
                    radius: 8
                    color: hot || editing ? Qt.rgba(1, 1, 1, 0.06) : "transparent"

                    // Click anywhere on the row (circle or text) to tick it.
                    MouseArea {
                      id: rowMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      enabled: !taskRow.editing
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.toggleTask(taskRow.index)
                    }
                    Rectangle {
                      id: check
                      anchors.left: parent.left
                      anchors.leftMargin: 4
                      anchors.verticalCenter: parent.verticalCenter
                      width: 18
                      height: 18
                      radius: 9
                      color: taskRow.modelData.done ? Color.accent : "transparent"
                      border.width: taskRow.modelData.done ? 0 : 1.5
                      border.color: Qt.rgba(1, 1, 1, 0.5)
                      Text { anchors.centerIn: parent; visible: taskRow.modelData.done; text: "󰄬"; color: "white"; font.family: root.iconFont; font.pixelSize: 11 }
                    }
                    Text {
                      id: taskText
                      visible: !taskRow.editing
                      anchors.left: check.right
                      anchors.leftMargin: 10
                      anchors.right: actions.left
                      anchors.rightMargin: 6
                      anchors.verticalCenter: parent.verticalCenter
                      text: taskRow.modelData.text
                      wrapMode: Text.Wrap
                      color: taskRow.modelData.done ? Qt.rgba(1, 1, 1, 0.4) : "white"
                      font.strikeout: taskRow.modelData.done
                      font.family: root.textFont
                      font.pixelSize: 13
                    }
                    TextInput {
                      id: editInput
                      visible: taskRow.editing
                      anchors.left: check.right
                      anchors.leftMargin: 10
                      anchors.right: parent.right
                      anchors.rightMargin: 8
                      anchors.verticalCenter: parent.verticalCenter
                      color: "white"
                      selectionColor: Qt.rgba(1, 1, 1, 0.3)
                      font.family: root.textFont
                      font.pixelSize: 13
                      clip: true
                      onVisibleChanged: if (visible) { text = taskRow.modelData.text; forceActiveFocus(); selectAll() }
                      onAccepted: root.renameTask(taskRow.index, text)
                      onActiveFocusChanged: if (!activeFocus && taskRow.editing) root.renameTask(taskRow.index, text)
                      Keys.onEscapePressed: root.editingTask = -1
                    }

                    // Pencil + red × only while hovering the task.
                    Row {
                      id: actions
                      anchors.right: parent.right
                      anchors.rightMargin: 6
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 10
                      visible: taskRow.hot && !taskRow.editing
                      Text {
                        text: "󰏫"
                        color: editMouse.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.6)
                        font.family: root.iconFont
                        font.pixelSize: 13
                        MouseArea {
                          id: editMouse
                          anchors.fill: parent
                          anchors.margins: -5
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.editingTask = taskRow.index
                        }
                      }
                      Text {
                        text: "󰅖"
                        color: delMouse.containsMouse ? "#ff6b5e" : "#ff453a"
                        font.family: root.iconFont
                        font.pixelSize: 14
                        MouseArea {
                          id: delMouse
                          anchors.fill: parent
                          anchors.margins: -5
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.deleteTask(taskRow.index)
                        }
                      }
                    }
                  }
                }
              }
            }
            Text {
              visible: root.tasks.some(function(t) { return t.done })
              text: "Clear completed"
              color: clearMouse.containsMouse ? "white" : Color.accent
              font.family: root.textFont
              font.weight: Font.DemiBold
              font.pixelSize: 11
              MouseArea {
                id: clearMouse
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.tasks = root.tasks.filter(function(t) { return !t.done }); root.saveNotesSoon() }
              }
            }
          }
        }
      }
    }
  }
}
