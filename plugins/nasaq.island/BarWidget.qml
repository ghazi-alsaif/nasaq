import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "Island.js" as Island
import "Weather.js" as Weather
import "../nasaq.commons" as Nasaq

// NASAQ: Apple-style Dynamic Island in the middle of the bar.
//
// Compact, it is the clock pill, with album art + a live waveform while music
// plays, or the next prayer's countdown when it is close. Click it to expand
// into a card (date, Hijri date, prayer times, now playing). It also owns the
// "osd" IPC target, so volume/brightness/mic changes morph out of it, and it
// announces prayer times. Right-click opens the stock calendar.
BarWidget {
  id: root
  moduleName: "nasaq.island"

  // ── Settings ─────────────────────────────────────────────────────
  readonly property string clockFormat: setting("format", "ddd d MMM h:mm AP")
  property var config: ({ latitude: 21.4225, longitude: 39.8262, city: "", method: 4, reminderMinutes: 5, prayerQuiet: false })

  readonly property string textFont: "IBM Plex Sans Arabic"
  readonly property string iconFont: Style.font.family
  readonly property color accent: Color.accent
  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  // Same glass look as the control-center pill and card.
  // Glass: the card is as see-through as the user's active windows (Control
  // Center > Windows > Transparency), and Hyprland blurs behind it (layer rule
  // in looknfeel.lua), so it follows the user's window settings like everything else.
  property real glassAlpha: 0.65
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/nasaq/windows.json"
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try { var a = Number(JSON.parse(text()).activeOpacity); if (isFinite(a)) root.glassAlpha = Math.max(0.2, Math.min(1, a)) } catch (e) {}
    }
  }
  // Theme colours throughout, so a theme change carries over: the card is the
  // theme background, highlights are the theme accent.
  readonly property color cardColor: Util.alpha(Color.background, glassAlpha)
  // Text or icon drawn on an accent fill: dark on a light accent, white on a dark one.
  readonly property color onAccent: (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.6 ? "#16181d" : "white"
  readonly property real pillHeight: Math.max(20, Math.min(root.barSize - 4, Style.bar.iconSlot))

  // ── Clock ────────────────────────────────────────────────────────
  SystemClock { id: clock; precision: SystemClock.Seconds }
  readonly property date now: clock.date
  readonly property string clockText: Qt.formatDateTime(now, clockFormat)

  // ── Media ────────────────────────────────────────────────────────
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
  readonly property bool hasMedia: player !== null
  readonly property bool playing: hasMedia && player.isPlaying
  property var bars: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

  // ── Prayer ───────────────────────────────────────────────────────
  property var prayerDay: null
  readonly property string hijriMode: Nasaq.Settings.get("island.hijri", "both")
  property string loadedDayKey: ""
  readonly property bool prayerEnabled: Nasaq.Settings.get("island.prayer", true)
  readonly property var nextPrayer: prayerEnabled ? Island.nextPrayer(prayerDay, now) : null
  readonly property real msToNext: nextPrayer ? nextPrayer.time.getTime() - now.getTime() : -1
  readonly property bool prayerSoon: nextPrayer !== null && msToNext >= 0 && msToNext <= 60 * 60 * 1000
  property var notified: ({})

  // ── Island state ─────────────────────────────────────────────────
  property bool expanded: false
  property bool osdActive: false
  property var osd: ({ icon: "", message: "", hasProgress: false, fraction: 0, duration: 1400 })
  property bool alertActive: false
  property string alertTitle: ""
  property string alertSubtitle: ""
  readonly property bool overlayWanted: expanded || osdActive || alertActive || notifActive

  // ── Notifications (iPhone-style: the island turns into the toast) ──
  // nasaq.notifications writes its newest toast to this file and owns the
  // timers; the island shows it and answers over IPC.
  property var notif: ({ count: 0 })
  readonly property bool notifActive: (notif.count || 0) > 0
  // The last toast, kept while the island shrinks back.
  property var notifShown: ({})
  onNotifChanged: {
    if ((notif.count || 0) > 0) notifShown = notif
    // Cleared from the notification center (or by us): drop the list now
    // instead of waiting for the next reload, so the pill's dot goes too.
    var c = Number(notif.clearedAt) || 0
    if (c > clearedAt) {
      clearedAt = c
      history = history.filter(function(e) { return (e.timestamp || 0) > c })
      historyRefresh.restart()
      // Already wiped elsewhere: a pending island Clear has nothing left to do
      // (and must not dismiss toasts that arrive in its remaining seconds).
      if (clearPending) { clearPending = false; clearTimer.stop() }
    }
  }
  // Moment of the last history wipe; older entries are never shown again.
  property double clearedAt: 0
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/nasaq/island-toast.json"
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { root.notif = JSON.parse(text()) } catch (e) { root.notif = { count: 0 } } }
  }
  function notifIcon(n) {
    if (!n) return ""
    var img = String(n.image || "")
    // Theme icons by name: resolve through the icon theme, and give up (the
    // bell glyph shows) when the theme doesn't have them, instead of Qt's
    // checkered "missing image" square.
    if (img.indexOf("image://icon/") === 0) return Quickshell.iconPath(img.slice(13), true)
    if (img.length > 0) return img.indexOf("/") === 0 ? "file://" + img : img
    var icon = String(n.appIcon || "")
    if (icon.length === 0) return ""
    if (icon.indexOf("/") === 0) return "file://" + icon
    if (icon.indexOf("file://") === 0 || icon.indexOf("image://") === 0) return icon
    return Quickshell.iconPath(icon, true)
  }
  // ── Notification list in the expanded card ──
  // Read straight from nasaq.notifications' history files (same user, plain
  // JSON), newest first. "Seen" = shown in an opened card; the time of the
  // newest one seen is kept in ~/.local/state/nasaq/island-seen.
  readonly property string historyDir: Quickshell.env("HOME") + "/.local/state/omarchy/notifications/history"
  property var history: []
  // Seen = at or before the baseline time, or individually marked since.
  // (One watermark cannot say "these five yes, the older three not yet".)
  property real lastSeen: 0
  property var seenSet: ({})
  function isSeen(e) { var t = (e && e.timestamp) || 0; return t <= lastSeen || seenSet[t] === true }
  readonly property int unseenCount: history.filter(function(e) { return !root.isSeen(e) }).length
  Process {
    id: historyProc
    command: ["bash", "-c", "awk 1 \"$1\"/*.json 2>/dev/null || true", "--", root.historyDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var list = []
        String(text || "").split("\n").forEach(function(line) {
          if (!line.trim()) return
          try { list.push(JSON.parse(line)) } catch (e) {}
        })
        // Anything from before the last Clear is on its way to deletion.
        list = list.filter(function(e) { return (e.timestamp || 0) > root.clearedAt })
        list.sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
        root.history = list
      }
    }
  }
  function reloadHistory() { if (!historyProc.running) historyProc.running = true }
  FileView {
    id: seenFile
    path: Quickshell.env("HOME") + "/.local/state/nasaq/island-seen"
    blockLoading: true
    printErrors: false
    onLoaded: {
      var raw = String(text()).trim()
      try {
        var o = JSON.parse(raw)
        if (typeof o === "number") { root.lastSeen = o; return }
        root.lastSeen = Number(o.baseline) || 0
        var set = {}
        ;(o.seen || []).forEach(function(t) { set[t] = true })
        root.seenSet = set
      } catch (e) { root.lastSeen = Number(raw) || 0 }
    }
  }
  readonly property int shownCount: 5
  function markSeenList(stamps) {
    var set = Object.assign({}, seenSet), changed = false
    stamps.forEach(function(t) { if (t > root.lastSeen && set[t] !== true) { set[t] = true; changed = true } })
    if (!changed) return
    // Everything in the list seen: fold the set into the baseline.
    var allSeen = history.every(function(e) { var t = e.timestamp || 0; return t <= root.lastSeen || set[t] === true })
    if (allSeen && history.length > 0) { lastSeen = history[0].timestamp || lastSeen; set = {} }
    seenSet = set
    seenFile.setText(JSON.stringify({ baseline: lastSeen, seen: Object.keys(set).map(Number) }) + "\n")
  }
  function setSeen(ts) { markSeenList([ts]) }
  // Closing the card marks exactly the rows it showed.
  function markSeen() {
    markSeenList(history.slice(0, shownCount).map(function(e) { return e.timestamp || 0 }))
  }
  // While Do Not Disturb is on, notifications go straight to history with no
  // toast, so nothing else would tell the island to look again.
  Timer { interval: 30000; repeat: true; running: root.notif.dnd === true; onTriggered: root.reloadHistory() }
  onExpandedChanged: {
    if (expanded) { reloadHistory(); return }
    // A pending Clear keeps its five seconds when the card closes, so the card
    // can be opened again to Undo it; clearTimer does the clear when it ends.
    if (!clearPending) markSeen()
  }
  // A toast that times out moves into history; refresh then.
  onNotifActiveChanged: if (!notifActive) historyRefresh.restart()
  Timer { id: historyRefresh; interval: 900; onTriggered: root.reloadHistory() }
  Component.onCompleted: reloadHistory()
  // Clear waits five seconds behind an Undo before it really deletes.
  property bool clearPending: false
  Timer { id: clearTimer; interval: 5000; onTriggered: root.doClear() }
  function doClear() {
    if (!clearPending) return
    clearPending = false
    clearTimer.stop()
    clearedAt = Date.now()
    notifCall("clear")        // history files
    notifCall("dismissAll")   // toasts still on screen (like the center's Clear All)
    seenSet = ({})
    lastSeen = clearedAt
    seenFile.setText(JSON.stringify({ baseline: lastSeen, seen: [] }) + "\n")
    history = []
    historyRefresh.restart()
    // The deletion runs in the service's queue; look again once it has had time.
    clearRecheck.restart()
  }
  Timer { id: clearRecheck; interval: 4000; onTriggered: root.reloadHistory() }
  function timeAgo(ts) {
    var diff = (Date.now() - ts) / 1000
    if (diff < 60) return "now"
    if (diff < 3600) return Math.floor(diff / 60) + "m"
    if (diff < 86400) return Math.floor(diff / 3600) + "h"
    if (diff < 172800) return "Yesterday"
    return Qt.formatDate(new Date(ts), "d MMM")
  }
  // A history entry has no live actions left: run its command if it carried
  // one (Omarchy toasts, the crash notice), otherwise jump to the app's window.
  // Same checks the notification service applies before running a toast's
  // command: a real array of words, a program name that is not an option.
  function safeArgv(raw) {
    var argv = null
    try { argv = raw ? JSON.parse(raw) : null } catch (err) { return null }
    if (!Array.isArray(argv) || argv.length === 0) return null
    for (var i = 0; i < argv.length; i++) if (typeof argv[i] !== "string") return null
    if (argv[0].length === 0 || argv[0].charAt(0) === "-") return null
    return argv
  }
  function openHistory(e) {
    var argv = safeArgv(e.execArgv)
    if (argv) Quickshell.execDetached(argv)
    else if (e.app) Quickshell.execDetached(["omarchy-hyprland-focus-app", String(e.app)])
    root.expanded = false
  }

  // History files keep no icon, so fall back to the app's desktop entry.
  function historyIcon(e) {
    var src = notifIcon(e)
    if (src) return src
    var entry = e && e.app ? DesktopEntries.heuristicLookup(String(e.app)) : null
    return entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : ""
  }

  // The toast on screen, by timestamp, so a newer arrival can't take the click.
  // Acting on it also counts as having seen it (it lands in history next).
  function notifAct(fn) {
    var ts = Number(notifShown.timestamp) || 0
    setSeen(ts)
    notifCall(fn, String(ts))
  }
  function isRtlText(t) { return /^[^A-Za-z]*[\u0590-\u08FF]/.test(String(t || "")) }

  function notifCall(fn, arg) {
    var cmd = ["omarchy-shell", "notifications", fn]
    if (arg !== undefined) cmd.push(arg)
    Quickshell.execDetached(cmd)
  }
  property bool overlayShown: false

  onOverlayWantedChanged: {
    if (overlayWanted) { collapseHide.stop(); overlayShown = true }
    else collapseHide.restart()
  }

  Timer { id: collapseHide; interval: 420; onTriggered: root.overlayShown = false }
  Timer { id: osdTimer; onTriggered: root.osdActive = false }
  Timer { id: popThrottle; interval: 90 }
  Timer { id: alertTimer; interval: 9000; onTriggered: root.alertActive = false }
  Timer { id: leaveTimer; interval: 650; onTriggered: { root.expanded = false; root.searching = false } }

  // ── Prayer location search (Open-Meteo geocoding, Arabic names work) ──
  property bool searching: false
  property string cityQuery: ""
  property var cityResults: []
  onCityQueryChanged: if (cityQuery.trim().length >= 2) geoTimer.restart(); else cityResults = []
  Timer {
    id: geoTimer
    interval: 300
    onTriggered: {
      if (geoProc.running) geoProc.running = false
      geoProc.command = ["bash", "-c",
        "curl -4 -sf --max-time 8 -G https://geocoding-api.open-meteo.com/v1/search --data-urlencode \"name=$1\" -d count=6 -d language=ar",
        "nasaq-geo", root.cityQuery.trim()]
      geoProc.running = true
    }
  }
  Process {
    id: geoProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.cityResults = JSON.parse(text).results || [] } catch (e) { root.cityResults = [] }
      }
    }
  }
  function setLocation(r) {
    var c = Object.assign({}, root.config, { city: r.name, latitude: r.latitude, longitude: r.longitude })
    root.config = c
    configFile.setText(JSON.stringify(c, null, 2) + "\n")
    root.searching = false
    root.cityQuery = ""
    root.cityResults = []
    root.loadedDayKey = ""
    root.refreshPrayer()
    root.weather = null
    root.refreshWeather()
  }

  function showOsd(payloadJson) {
    osd = Island.osdState(payloadJson)
    // NASAQ: macOS-style pop on volume changes (throttled; silent when muted).
    var osdIcon = ""
    try { osdIcon = String(JSON.parse(payloadJson || "{}").icon || "") } catch (e) {}
    if (/^volume/i.test(osdIcon) && !/mute/i.test(osdIcon) && osd.hasProgress && osd.fraction > 0 && !popThrottle.running) {
      popThrottle.start()
      Quickshell.execDetached(["nasaq-sound", "volume"])
    }
    osdActive = true
    if (osd.duration > 0) { osdTimer.interval = osd.duration; osdTimer.restart() }
    else osdTimer.stop()
  }

  function showAlert(title, subtitle, ms) {
    // Same soft chime as notifications; silent while sounds are switched off.
    Quickshell.execDetached(["nasaq-sound", "notify"])
    alertTitle = title
    alertSubtitle = subtitle
    alertActive = true
    alertTimer.interval = ms || 9000
    alertTimer.restart()
  }

  // ── Stopwatch (NASAQ) ─────────────────────────────────────────────
  // omarchy-shell nasaq.island stopwatch start|stop|toggle|reset|lap
  property bool swRunning: false
  property real swStart: 0
  property real swAccum: 0
  property real swNow: 0
  property var swLaps: []
  readonly property bool swActive: swRunning || swAccum > 0
  readonly property real swElapsed: swAccum + (swRunning ? Math.max(0, swNow - swStart) : 0)
  function swFormat(ms) {
    var t = Math.floor(ms / 1000), h = Math.floor(t / 3600), m = Math.floor(t / 60) % 60, sec = t % 60
    var tenth = Math.floor(ms / 100) % 10
    var mm = (h > 0 && m < 10 ? "0" : "") + m, ss = (sec < 10 ? "0" : "") + sec
    return (h > 0 ? h + ":" : "") + mm + ":" + ss + (h > 0 ? "" : "." + tenth)
  }
  function swStartFn() { if (!swRunning) { swStart = Date.now(); swNow = swStart; swRunning = true } }
  function swStopFn() { if (swRunning) { swAccum += Date.now() - swStart; swRunning = false } }
  function swToggle() { if (swRunning) swStopFn(); else swStartFn() }
  function swReset() { swRunning = false; swAccum = 0; swLaps = [] }
  function swLap() { if (swActive) { var l = swLaps.slice(); l.unshift(swElapsed); swLaps = l.slice(0, 5) } }
  Timer { interval: 100; repeat: true; running: root.swRunning; onTriggered: root.swNow = Date.now() }
  IpcHandler {
    target: "nasaq.stopwatch"
    function start(): string { root.swStartFn(); return "running" }
    function stop(): string { root.swStopFn(); return root.swFormat(root.swElapsed) }
    function toggle(): string { root.swToggle(); return root.swRunning ? "running" : root.swFormat(root.swElapsed) }
    function reset(): string { root.swReset(); return "reset" }
    function lap(): string { root.swLap(); return root.swFormat(root.swElapsed) }
    function status(): string { return JSON.stringify({ running: root.swRunning, elapsedMs: Math.round(root.swElapsed), text: root.swFormat(root.swElapsed) }) }
  }

  // ── Pomodoro (NASAQ, TEST) ───────────────────────────────────────
  // omarchy-shell nasaq.pomodoro start|stop|skip|status
  property bool pomoActive: false
  property string pomoPhase: "work"
  property real pomoEnd: 0
  property real pomoNow: 0
  property int pomoCycle: 1
  readonly property int pomoWork: Nasaq.Settings.get("pomodoro.work", 25)
  readonly property int pomoBreak: Nasaq.Settings.get("pomodoro.break", 5)
  readonly property int pomoLong: Nasaq.Settings.get("pomodoro.longBreak", 15)
  readonly property real pomoLeft: Math.max(0, pomoEnd - pomoNow)
  function pomoFormat(ms) { var t = Math.ceil(ms / 1000), m = Math.floor(t / 60), sec = t % 60; return m + ":" + (sec < 10 ? "0" : "") + sec }
  function pomoBegin(phase) {
    pomoPhase = phase
    var mins = phase === "work" ? pomoWork : (pomoCycle % 4 === 0 ? pomoLong : pomoBreak)
    pomoNow = Date.now(); pomoEnd = pomoNow + mins * 60000; pomoActive = true
  }
  function pomoStart() { pomoCycle = 1; pomoBegin("work"); showAlert("Focus", root.pomoWork + " minutes · cycle 1 of 4", 4000) }
  function pomoStop() { pomoActive = false }
  function pomoNext() {
    if (pomoPhase === "work") { pomoBegin("break"); showAlert("Break", (pomoCycle % 4 === 0 ? pomoLong : pomoBreak) + " minutes — stand up, look away", 9000) }
    else { pomoCycle++; pomoBegin("work"); showAlert("Focus", pomoWork + " minutes · cycle " + ((pomoCycle - 1) % 4 + 1) + " of 4", 6000) }
    Quickshell.execDetached(["nasaq-sound", "notify"])
  }
  Timer { interval: 1000; repeat: true; running: root.pomoActive
    onTriggered: { root.pomoNow = Date.now(); if (root.pomoLeft <= 0) root.pomoNext() } }
  IpcHandler {
    target: "nasaq.pomodoro"
    function start(): string { root.pomoStart(); return "focus" }
    function stop(): string { root.pomoStop(); return "stopped" }
    function skip(): string { if (root.pomoActive) root.pomoNext(); return root.pomoPhase }
    function toggle(): string { if (root.pomoActive) root.pomoStop(); else root.pomoStart(); return root.pomoActive ? "focus" : "stopped" }
    function status(): string { return JSON.stringify({ active: root.pomoActive, phase: root.pomoPhase, left: root.pomoFormat(root.pomoLeft), cycle: root.pomoCycle }) }
  }

  // ── Compact layout (lives in the bar) ────────────────────────────
  // Priority in the side slots: now playing > stopwatch > next prayer.
  readonly property bool sideInfo: !playing && (swActive || pomoActive || prayerSoon)
  readonly property bool showLeftSlot: playing || sideInfo
  readonly property bool showRightSlot: playing || sideInfo
  readonly property real compactWidth: clockLabel.implicitWidth + 28
    + (showLeftSlot ? pillHeight + 4 : 0)
    + (showRightSlot ? (playing ? 30 : prayerLabel.implicitWidth + 10) : 0)

  implicitWidth: compactWidth
  implicitHeight: Style.bar.iconSlot
  Behavior on implicitWidth { SpringAnimation { spring: 3.5; damping: 0.35 } }

  Rectangle {
    id: pill
    anchors.centerIn: parent
    width: parent.width
    height: root.pillHeight
    radius: height / 2
    color: Util.alpha(root.barForeground, pillMouse.containsMouse ? 0.16 : 0.08)
    opacity: root.overlayShown ? 0 : 1
    Behavior on color { ColorAnimation { duration: 120 } }

    Item {
      id: leftSlot
      anchors.left: parent.left
      anchors.leftMargin: 4
      anchors.verticalCenter: parent.verticalCenter
      width: root.showLeftSlot ? root.pillHeight - 6 : 0
      height: root.pillHeight - 6
      visible: width > 0

      Rectangle {
        anchors.fill: parent
        radius: height / 2
        clip: true
        color: "#1c1c1e"
        visible: root.playing
        Image {
          anchors.fill: parent
          source: root.player && root.player.trackArtUrl ? root.player.trackArtUrl : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          visible: status === Image.Ready
        }
        Text {
          anchors.centerIn: parent
          text: "󰝚"
          color: root.accent
          font.family: root.iconFont
          font.pixelSize: 11
          visible: !root.player || !root.player.trackArtUrl
        }
      }
      Text {
        anchors.centerIn: parent
        visible: root.sideInfo
        text: root.swActive ? "󱎫" : root.pomoActive ? (root.pomoPhase === "work" ? "󱎫" : "󰅶") : "󰽥"
        color: root.accent
        font.family: root.iconFont
        font.pixelSize: 13
      }
    }

    Text {
      id: clockLabel
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: ((root.showLeftSlot ? root.pillHeight + 4 : 0)
        - (root.showRightSlot ? (root.playing ? 30 : prayerLabel.implicitWidth + 10) : 0)) / 2
      text: root.clockText
      color: root.barForeground
      // The UI face with fixed-width digits, the same as the card's clock.
      font.family: root.textFont
      font.features: ({ "tnum": 1 })
      font.pixelSize: Style.font.body
      font.weight: Font.DemiBold
    }

    Item {
      anchors.right: parent.right
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      width: root.showRightSlot ? (root.playing ? 22 : prayerLabel.implicitWidth) : 0
      height: root.pillHeight - 8
      visible: width > 0

      Row {
        anchors.centerIn: parent
        spacing: 2
        visible: root.playing
        Repeater {
          model: 5
          delegate: Rectangle {
            required property int index
            width: 3
            radius: 1.5
            anchors.verticalCenter: parent.verticalCenter
            height: Math.max(3, (root.pillHeight - 10) * (root.bars[index * 3] || 0) / 100)
            color: root.accent
            Behavior on height { NumberAnimation { duration: 60 } }
          }
        }
      }
      Text {
        id: prayerLabel
        anchors.centerIn: parent
        visible: root.sideInfo
        text: root.swActive ? root.swFormat(root.swElapsed)
            : root.pomoActive ? (root.pomoPhase === "work" ? "Focus " : "Break ") + root.pomoFormat(root.pomoLeft)
            : root.nextPrayer ? root.nextPrayer.name + " " + Island.formatCountdown(root.msToNext) : ""
        font.features: ({ "tnum": 1 })
        opacity: root.swActive && !root.swRunning ? 0.6 : 1
        color: root.accent
        font.family: root.textFont
        font.pixelSize: Style.font.body - 1
        font.weight: Font.DemiBold
      }
    }

    // Visible without opening anything: a dot for notifications not seen yet.
    // (Do Not Disturb already shows as the bell-off icon in the bar's indicators.)
    Rectangle {
      visible: root.unseenCount > 0
      anchors.right: parent.right
      anchors.top: parent.top
      // Inside the pill's rounded end, not hanging off its corner.
      anchors.rightMargin: 5
      anchors.topMargin: 4
      width: 7
      height: 7
      radius: 3.5
      color: root.accent
    }
    MouseArea {
      id: pillMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          Quickshell.execDetached(["omarchy-shell", "nasaq.notifcenter", "toggle"])
          return
        }
        root.expanded = true
        leaveTimer.stop()
      }
    }
  }

  // ── Overlay: the island grows out of the pill ────────────────────
  PanelWindow {
    id: overlay
    screen: pill.QsWindow.window ? pill.QsWindow.window.screen : null
    visible: root.overlayShown
    anchors { top: true; left: true; right: true }
    implicitHeight: 860
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nasaq-island"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.searching ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: Region { item: shape }

    // Where the pill sits in the bar, in this window's (screen) coordinates.
    readonly property point pillPos: {
      var unused = root.compactWidth + root.width + overlay.width
      // The floating bar window sits inset from the screen edges.
      var w = pill.QsWindow.window
      var p = pill.mapToItem(null, 0, 0)
      var ml = w && w.margins ? (w.margins.left || 0) : 0
      var mt = w && w.margins ? (w.margins.top || 0) : 0
      return Qt.point(p.x + ml, p.y + mt)
    }
    readonly property real centerX: pillPos.x + pill.width / 2
    readonly property real topY: pillPos.y

    readonly property string mode: root.expanded ? "expanded"
      : root.osdActive ? "osd"
      : root.alertActive ? "alert"
      : root.notifActive ? "notif"
      : "compact"

    Rectangle {
      id: shape
      color: overlay.mode === "compact" ? Util.alpha(root.barForeground, 0.16) : root.cardColor
      border.color: Qt.rgba(1, 1, 1, overlay.mode === "compact" ? 0 : 0.14)
      border.width: 1
      Behavior on color { ColorAnimation { duration: 200 } }
      y: overlay.topY
      x: overlay.centerX - width / 2
      width: overlay.mode === "expanded" ? 440
        : overlay.mode === "alert" ? Math.max(340, alertCol.implicitWidth + 100)
        : overlay.mode === "osd" ? 340
        : overlay.mode === "notif" ? 420
        : pill.width
      height: overlay.mode === "expanded" ? expandedCol.implicitHeight + 36
        : overlay.mode === "alert" ? 72
        : overlay.mode === "osd" ? root.pillHeight + 16
        : overlay.mode === "notif" ? Math.max(72, notifRow.implicitHeight + 28)
        : root.pillHeight
      radius: overlay.mode === "expanded" ? 32 : overlay.mode === "alert" || overlay.mode === "notif" ? 30 : height / 2
      clip: true
      Behavior on width { SpringAnimation { spring: 3.2; damping: 0.30; epsilon: 0.5 } }
      Behavior on height { SpringAnimation { spring: 3.2; damping: 0.32; epsilon: 0.5 } }
      Behavior on radius { NumberAnimation { duration: 220 } }

      // Hover over the WHOLE card, children included. A MouseArea's
      // containsMouse drops the moment the pointer enters a child MouseArea
      // (a history row, ×, Change…), which used to start the leave timer and
      // collapse the island while the pointer was still on it.
      HoverHandler {
        id: cardHover
        onHoveredChanged: {
          if (hovered) leaveTimer.stop()
          else if (root.expanded && !root.searching) leaveTimer.restart()
        }
        // Hovering a toast pauses its timer. A property over both conditions,
        // so it also fires when a toast arrives under a pointer already here.
        readonly property bool notifHover: hovered && overlay.mode === "notif"
        onNotifHoverChanged: root.notifCall("islandHover", notifHover ? "true" : "false")
      }
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
          // A notification: click opens it, right-click (or ×) dismisses it.
          if (overlay.mode === "notif") {
            root.notifAct(mouse.button === Qt.RightButton ? "islandDismiss" : "islandInvoke")
            return
          }
          if (mouse.button === Qt.RightButton) { root.expanded = false; return }
          if (!root.expanded) { root.expanded = true; root.osdActive = false; root.alertActive = false }
        }
      }

      // Compact clock, shown while morphing back.
      Text {
        anchors.centerIn: parent
        visible: overlay.mode === "compact"
        text: root.clockText
        color: root.barForeground
        font.family: root.textFont
        font.features: ({ "tnum": 1 })
        font.pixelSize: Style.font.body
        font.weight: Font.DemiBold
      }

      // ── OSD ──
      Row {
        anchors.centerIn: parent
        spacing: 14
        opacity: overlay.mode === "osd" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 140 } }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.osd.icon
          color: "white"
          font.family: root.iconFont
          font.pixelSize: 18
        }
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.osd.hasProgress
          width: 200
          height: 6
          radius: 3
          color: Qt.rgba(1, 1, 1, 0.2)
          Rectangle {
            height: parent.height
            radius: 3
            width: parent.width * root.osd.fraction
            color: "white"
            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
          }
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.osd.message
          color: "white"
          font.family: root.textFont
          font.weight: Font.DemiBold
          font.pixelSize: 13
          width: root.osd.hasProgress ? 38 : implicitWidth
          horizontalAlignment: Text.AlignRight
          elide: Text.ElideRight
        }
      }

      // ── Notification ──
      Row {
        id: notifRow
        x: 16
        y: 14
        width: 420 - 32
        spacing: 12
        opacity: overlay.mode === "notif" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        // An Arabic toast reads right to left as a whole: icon on the right,
        // every line starting from the right edge.
        LayoutMirroring.enabled: root.isRtlText(root.notifShown.summary)
        LayoutMirroring.childrenInherit: true

        Rectangle {
          id: notifIconBox
          width: 44
          height: 44
          radius: 12
          color: Qt.rgba(1, 1, 1, 0.10)
          clip: true
          Image {
            id: notifImg
            anchors.fill: parent
            anchors.margins: String(root.notifShown.image || "").length > 0 ? 0 : 6
            source: root.historyIcon(root.notifShown)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 88
            sourceSize.height: 88
            visible: status === Image.Ready
          }
          Text {
            anchors.centerIn: parent
            visible: notifImg.status !== Image.Ready
            text: String(root.notifShown.glyph || "").length > 0 ? root.notifShown.glyph : "󰂚"
            color: "white"
            font.family: root.iconFont
            font.pixelSize: 20
          }
        }

        Column {
          width: notifRow.width - notifIconBox.width - notifRow.spacing
          spacing: 1
          // The close button sits beside the first two lines only; the body
          // below it uses the full width.
          readonly property real closeGap: 30
          readonly property bool rtl: root.isRtlText(root.notifShown.summary)
          Item {
            width: parent.width - parent.closeGap
            x: parent.rtl ? parent.closeGap : 0
            height: notifApp.implicitHeight
            Text {
              id: notifApp
              anchors.left: parent.left
              anchors.right: notifMore.left
              anchors.rightMargin: 6
              text: String(root.notifShown.app || "")
              color: Qt.rgba(1, 1, 1, 0.55)
              font.family: root.textFont
              font.pixelSize: 11
              horizontalAlignment: Text.AlignLeft
              elide: Text.ElideRight
            }
            Text {
              id: notifMore
              anchors.right: parent.right
              visible: (root.notif.count || 0) > 1
              text: "+" + ((root.notif.count || 1) - 1)
              color: Qt.rgba(1, 1, 1, 0.55)
              font.family: root.textFont
              font.pixelSize: 11
              font.weight: Font.DemiBold
              // The others are one click away: open the card with the list.
              MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.expanded = true; leaveTimer.stop() }
              }
            }
          }
          Text {
            width: parent.width - parent.closeGap
            x: parent.rtl ? parent.closeGap : 0
            text: String(root.notifShown.summary || "")
            color: "white"
            font.family: root.textFont
            font.weight: Font.Bold
            font.pixelSize: 14
            horizontalAlignment: Text.AlignLeft
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            visible: text.length > 0
            text: String(root.notifShown.body || "").replace(/<[^>]*>/g, "")
            color: Qt.rgba(1, 1, 1, 0.75)
            font.family: root.textFont
            font.pixelSize: 12
            horizontalAlignment: Text.AlignLeft
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }
        }
      }

      // Close button for the toast: a visible way out (right-click also works).
      Rectangle {
        visible: overlay.mode === "notif"
        width: 22
        height: 22
        radius: 11
        y: 12
        x: root.isRtlText(root.notifShown.summary) ? 12 : parent.width - width - 12
        color: Qt.rgba(1, 1, 1, closeMouse.containsMouse ? 0.24 : 0.12)
        Text {
          anchors.centerIn: parent
          text: "󰅖"
          color: "white"
          font.family: root.iconFont
          font.pixelSize: 11
        }
        MouseArea {
          id: closeMouse
          anchors.fill: parent
          anchors.margins: -4
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.notifAct("islandDismiss")
        }
      }

      // ── Alert (prayer) ──
      Row {
        anchors.centerIn: parent
        spacing: 14
        opacity: overlay.mode === "alert" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: 42
          height: 42
          radius: 21
          color: Util.alpha(root.accent, 0.18)
          Text {
            anchors.centerIn: parent
            text: "󰽥"
            color: root.accent
            font.family: root.iconFont
            font.pixelSize: 20
          }
        }
        Column {
          id: alertCol
          anchors.verticalCenter: parent.verticalCenter
          spacing: 1
          Text {
            text: root.alertTitle
            color: "white"
            font.family: root.textFont
            font.weight: Font.Bold
            font.pixelSize: 16
          }
          Text {
            text: root.alertSubtitle
            visible: text.length > 0
            color: Qt.rgba(1, 1, 1, 0.6)
            font.family: root.textFont
            font.pixelSize: 12
          }
        }
      }

      // ── Expanded card ──
      Column {
        id: expandedCol
        x: 22
        y: 18
        width: 440 - 44
        spacing: 14
        opacity: overlay.mode === "expanded" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180 } }

        // Stopwatch row (only while one is running or paused)
        Item {
          visible: root.swActive
          width: parent.width
          height: visible ? 34 : 0
          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "󱎫  " + root.swFormat(root.swElapsed) + (root.swLaps.length ? "   ·   lap " + root.swFormat(root.swLaps[0]) : "")
            color: "white"
            font.family: root.textFont
            font.features: ({ "tnum": 1 })
            font.pixelSize: 15
            font.weight: Font.DemiBold
          }
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Repeater {
              model: [{ t: root.swRunning ? "Pause" : "Resume", a: "toggle" }, { t: "Lap", a: "lap" }, { t: "Reset", a: "reset" }]
              delegate: Rectangle {
                required property var modelData
                width: swBtn.implicitWidth + 18; height: 24; radius: 12
                color: Qt.rgba(1, 1, 1, swMouse.containsMouse ? 0.22 : 0.12)
                Text { id: swBtn; anchors.centerIn: parent; text: modelData.t; color: "white"; font.family: root.textFont; font.pixelSize: 12 }
                MouseArea {
                  id: swMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: modelData.a === "toggle" ? root.swToggle() : modelData.a === "lap" ? root.swLap() : root.swReset()
                }
              }
            }
          }
        }

        // Date + Hijri
        Item {
          width: parent.width
          height: 40
          Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            Text {
              readonly property string hijriText: root.prayerDay ? root.prayerDay.hijri.day + " " + root.prayerDay.hijri.month + " " + root.prayerDay.hijri.year + " هـ" : ""
              // NASAQ Settings > Widgets > Date: both | hijri | gregorian
              text: root.hijriMode === "hijri" && hijriText ? hijriText : Qt.locale("en_US").toString(root.now, "dddd, d MMMM")
              color: "white"
              font.family: root.textFont
              font.weight: Font.Bold
              font.pixelSize: 16
            }
            Text {
              visible: root.prayerDay !== null && root.hijriMode === "both"
              text: root.prayerDay ? root.prayerDay.hijri.day + " " + root.prayerDay.hijri.month + " " + root.prayerDay.hijri.year + " هـ" : ""
              color: Qt.rgba(1, 1, 1, 0.6)
              font.family: root.textFont
              font.pixelSize: 12
            }
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.locale("en_US").toString(root.now, "h:mm AP").replace(/\s*[AP]M$/i, "")
            color: "white"
            font.family: root.textFont
            font.weight: Font.Bold
            font.pixelSize: 28
          }
        }

        // Prayer times
        Rectangle {
          width: parent.width
          height: 70
          radius: 18
          color: Qt.rgba(1, 1, 1, 0.07)
          visible: root.prayerEnabled && root.prayerDay !== null

          Row {
            anchors.fill: parent
            anchors.margins: 8
            layoutDirection: Qt.RightToLeft
            Repeater {
              model: root.prayerDay ? root.prayerDay.prayers : []
              delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property bool isNext: root.nextPrayer !== null && root.nextPrayer.index === index
                width: (parent.width) / 5
                height: parent.height
                radius: 12
                color: isNext ? Util.alpha(root.accent, 0.16) : "transparent"
                Column {
                  anchors.centerIn: parent
                  spacing: 2
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.name
                    color: isNext ? root.accent : Qt.rgba(1, 1, 1, 0.65)
                    font.family: root.textFont
                    font.weight: Font.DemiBold
                    font.pixelSize: 12
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Island.formatTime(modelData.time)
                    color: "white"
                    font.family: root.textFont
                    font.weight: isNext ? Font.Bold : Font.Normal
                    font.pixelSize: 15
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: isNext
                    text: "in " + Island.formatCountdown(root.msToNext)
                    color: root.accent
                    font.family: root.textFont
                    font.pixelSize: 10
                  }
                }
              }
            }
          }
        }

        // Prayer location: shows the city; "Change" turns into a search box.
        Item {
          width: parent.width
          height: root.searching ? searchCol.implicitHeight : 20

          Row {
            anchors.left: parent.left
            visible: !root.searching
            spacing: 6
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: String.fromCodePoint(0xf034e)
              color: Qt.rgba(1, 1, 1, 0.55)
              font.family: root.iconFont
              font.pixelSize: 13
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Prayer times · " + (root.config.city || "")
              color: Qt.rgba(1, 1, 1, 0.6)
              font.family: root.textFont
              font.pixelSize: 12
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "· Change"
              color: changeMouse.containsMouse ? "white" : root.accent
              font.family: root.textFont
              font.weight: Font.DemiBold
              font.pixelSize: 12
              MouseArea {
                id: changeMouse
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.searching = true
                  leaveTimer.stop()
                  Qt.callLater(function() { cityInput.forceActiveFocus() })
                }
              }
            }
          }

          Column {
            id: searchCol
            width: parent.width
            visible: root.searching
            spacing: 4

            Rectangle {
              width: parent.width
              height: 34
              radius: 10
              color: Qt.rgba(1, 1, 1, 0.10)
              border.color: Qt.rgba(1, 1, 1, cityInput.activeFocus ? 0.3 : 0.1)
              TextInput {
                id: cityInput
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignRight
                color: "white"
                font.family: root.textFont
                font.pixelSize: 13
                clip: true
                onTextChanged: root.cityQuery = text
                Keys.onEscapePressed: { text = ""; root.searching = false }
                Keys.onReturnPressed: if (root.cityResults.length > 0) root.setLocation(root.cityResults[0])
              }
              Text {
                anchors.fill: cityInput
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignRight
                visible: cityInput.text.length === 0
                text: "Search for a city…"
                color: Qt.rgba(1, 1, 1, 0.4)
                font.family: root.textFont
                font.pixelSize: 13
              }
            }

            Repeater {
              model: root.cityResults
              delegate: Rectangle {
                required property var modelData
                width: searchCol.width
                height: 34
                radius: 8
                color: cityMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                Column {
                  anchors.right: parent.right
                  anchors.rightMargin: 10
                  anchors.verticalCenter: parent.verticalCenter
                  Text {
                    anchors.right: parent.right
                    text: modelData.name
                    color: "white"
                    font.family: root.textFont
                    font.pixelSize: 13
                  }
                  Text {
                    anchors.right: parent.right
                    text: [modelData.admin1, modelData.country].filter(function(x) { return !!x }).join(", ")
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.family: root.textFont
                    font.pixelSize: 10
                  }
                }
                MouseArea {
                  id: cityMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setLocation(modelData)
                }
              }
            }
          }
        }

        // Now playing
        Item {
          width: parent.width
          height: 92
          visible: root.hasMedia

          Rectangle {
            id: art
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
              color: root.accent
              font.family: root.iconFont
              font.pixelSize: 26
            }
          }

          Column {
            anchors.left: art.right
            anchors.leftMargin: 14
            anchors.right: waveRow.left
            anchors.rightMargin: 10
            anchors.top: art.top
            anchors.topMargin: 6
            spacing: 2
            Text {
              width: parent.width
              text: root.player ? (root.player.trackTitle || "") : ""
              color: "white"
              font.family: root.textFont
              font.weight: Font.Bold
              font.pixelSize: 15
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              text: root.player ? (root.player.trackArtist || root.player.identity || "") : ""
              color: Qt.rgba(1, 1, 1, 0.6)
              font.family: root.textFont
              font.pixelSize: 13
              elide: Text.ElideRight
            }
          }

          Row {
            id: waveRow
            anchors.right: parent.right
            anchors.top: art.top
            anchors.topMargin: 8
            height: 26
            spacing: 2
            Repeater {
              model: 10
              delegate: Rectangle {
                required property int index
                width: 3
                radius: 1.5
                anchors.bottom: parent.bottom
                height: root.playing ? Math.max(3, 26 * (root.bars[index + 3] || 0) / 100) : 3
                color: root.accent
                Behavior on height { NumberAnimation { duration: 60 } }
              }
            }
          }

          // Progress
          Item {
            id: progress
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: art.bottom
            anchors.topMargin: 10
            height: 14
            visible: root.player && root.player.length > 0
            readonly property real frac: root.player && root.player.length > 0 ? Math.min(1, root.player.position / root.player.length) : 0
            Text {
              id: posText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: root.player ? Island.formatMediaTime(root.player.position) : ""
              color: Qt.rgba(1, 1, 1, 0.55)
              font.family: root.textFont
              font.pixelSize: 10
              width: 34
            }
            Rectangle {
              anchors.left: posText.right
              anchors.right: lenText.left
              anchors.rightMargin: 6
              anchors.verticalCenter: parent.verticalCenter
              height: 4
              radius: 2
              color: Qt.rgba(1, 1, 1, 0.2)
              Rectangle {
                width: parent.width * progress.frac
                height: parent.height
                radius: 2
                color: "white"
              }
              MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                enabled: root.player && root.player.canSeek
                cursorShape: Qt.PointingHandCursor
                onClicked: function(m) { root.player.position = root.player.length * Math.max(0, Math.min(1, (m.x - 6) / (width - 12))) }
              }
            }
            Text {
              id: lenText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.player ? "-" + Island.formatMediaTime(root.player.length - root.player.position) : ""
              color: Qt.rgba(1, 1, 1, 0.55)
              font.family: root.textFont
              font.pixelSize: 10
            }
          }
        }

        // Controls
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 34
          visible: root.hasMedia
          Repeater {
            model: [
              { icon: "󰒮", act: "prev", size: 22 },
              { icon: root.playing ? "󰏤" : "󰐊", act: "toggle", size: 30 },
              { icon: "󰒭", act: "next", size: 22 }
            ]
            delegate: Text {
              required property var modelData
              text: modelData.icon
              color: ctlMouse.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.85)
              font.family: root.iconFont
              font.pixelSize: modelData.size
              MouseArea {
                id: ctlMouse
                anchors.fill: parent
                anchors.margins: -8
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (!root.player) return
                  if (modelData.act === "prev" && root.player.canGoPrevious) root.player.previous()
                  else if (modelData.act === "next" && root.player.canGoNext) root.player.next()
                  else if (modelData.act === "toggle" && root.player.canTogglePlaying) root.player.togglePlaying()
                }
              }
            }
          }
        }

        Text {
          visible: !root.hasMedia && (root.prayerDay === null || !root.prayerEnabled)
          text: "Nothing playing"
          color: Qt.rgba(1, 1, 1, 0.5)
          font.family: root.textFont
          font.pixelSize: 13
        }

        // ── Quiet at prayer time (optional) ──
        Item {
          width: parent.width
          height: 22
          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Quiet for 20 min at prayer time"
            color: Qt.rgba(1, 1, 1, 0.7)
            font.family: root.textFont
            font.pixelSize: 12
          }
          Rectangle {
            id: quietSwitch
            readonly property bool on: root.config.prayerQuiet === true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            height: 20
            radius: 10
            color: on ? root.accent : Qt.rgba(1, 1, 1, 0.22)
            Behavior on color { ColorAnimation { duration: 140 } }
            Rectangle {
              width: 16
              height: 16
              radius: 8
              y: 2
              x: quietSwitch.on ? quietSwitch.width - width - 2 : 2
              color: "white"
              Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }
            MouseArea {
              anchors.fill: parent
              anchors.margins: -4
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setPrayerQuiet(!quietSwitch.on)
            }
          }
        }

        // ── Weather (same city as the prayer times) ──
        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.10); visible: root.weather !== null }
        Item {
          visible: root.weather !== null
          width: parent.width
          height: visible ? 58 : 0
          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.weather ? root.weather.icon : ""
              color: root.accent
              font.family: root.iconFont
              font.pixelSize: 30
            }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0
              Row {
                spacing: 6
                Text {
                  text: root.weather ? root.weather.temp + "°" : ""
                  color: "white"
                  font.family: root.textFont
                  font.weight: Font.DemiBold
                  font.pixelSize: 24
                  font.features: ({ "tnum": 1 })
                }
                Text {
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: 5
                  text: root.weather ? root.weather.label : ""
                  color: Qt.rgba(1, 1, 1, 0.75)
                  font.family: root.textFont
                  font.pixelSize: 13
                }
              }
              Text {
                text: root.weather ? "󰖎 " + root.weather.humidity + "%   󰖝 " + root.weather.wind + " km/h" : ""
                color: Qt.rgba(1, 1, 1, 0.5)
                font.family: root.textFont
                font.pixelSize: 11
              }
            }
          }
          // Five-day strip on the right: day, icon, high/low.
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Repeater {
              model: root.weather ? root.weather.days.slice(1, 5) : []
              delegate: Column {
                required property var modelData
                spacing: 1
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: modelData.name
                  color: Qt.rgba(1, 1, 1, 0.5)
                  font.family: root.textFont
                  font.pixelSize: 10
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: modelData.icon
                  color: Qt.rgba(1, 1, 1, 0.85)
                  font.family: root.iconFont
                  font.pixelSize: 15
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: modelData.max + "° " + modelData.min + "°"
                  color: Qt.rgba(1, 1, 1, 0.6)
                  font.family: root.textFont
                  font.pixelSize: 10
                  font.features: ({ "tnum": 1 })
                }
              }
            }
          }
        }

        // ── Notifications ──
        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.10) }

        Item {
          width: parent.width
          height: 24
          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Notifications"
              color: "white"
              font.family: root.textFont
              font.weight: Font.Bold
              font.pixelSize: 14
            }
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              visible: root.unseenCount > 0
              width: newText.implicitWidth + 12
              height: 18
              radius: 9
              color: root.accent
              Text {
                id: newText
                anchors.centerIn: parent
                text: root.unseenCount + " new"
                color: root.onAccent
                font.family: root.textFont
                font.pixelSize: 10
                font.weight: Font.DemiBold
              }
            }
          }
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Repeater {
              model: [
                { label: root.clearPending ? "Undo" : "Clear", act: "clear", show: root.history.length > 0 },
                { label: "All", act: "all", show: true }
              ]
              delegate: Rectangle {
                required property var modelData
                visible: modelData.show
                width: btnText.implicitWidth + 16
                height: 22
                radius: 11
                color: Qt.rgba(1, 1, 1, btnMouse.containsMouse ? 0.18 : 0.10)
                Text {
                  id: btnText
                  anchors.centerIn: parent
                  text: modelData.label
                  color: "white"
                  font.family: root.textFont
                  font.pixelSize: 11
                  font.weight: Font.DemiBold
                }
                MouseArea {
                  id: btnMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (modelData.act === "clear") {
                      if (root.clearPending) { root.clearPending = false; clearTimer.stop() }
                      else { root.clearPending = true; clearTimer.restart() }
                    } else {
                      root.expanded = false
                      Quickshell.execDetached(["omarchy-shell", "nasaq.notifcenter", "open"])
                    }
                  }
                }
              }
            }
          }
        }

        Text {
          visible: root.history.length === 0 || root.clearPending
          text: root.clearPending ? "Cleared. Undo is there for five seconds." : "No notifications"
          color: Qt.rgba(1, 1, 1, 0.5)
          font.family: root.textFont
          font.pixelSize: 12
        }

        Column {
          width: parent.width
          spacing: 2
          visible: root.history.length > 0 && !root.clearPending
          Repeater {
            model: root.history.slice(0, root.shownCount)
            delegate: Rectangle {
              required property var modelData
              readonly property bool unseen: !root.isSeen(modelData)
              // An Arabic row reads right to left as a whole, like the toast.
              LayoutMirroring.enabled: root.isRtlText(modelData.summary || modelData.app)
              LayoutMirroring.childrenInherit: true
              width: parent.width
              height: 50
              radius: 12
              color: histMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04)

              Rectangle {
                id: histIcon
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 34
                radius: 9
                color: Qt.rgba(1, 1, 1, 0.10)
                clip: true
                Image {
                  id: histImg
                  anchors.fill: parent
                  anchors.margins: 4
                  source: root.historyIcon(modelData)
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  sourceSize.width: 68
                  sourceSize.height: 68
                  visible: status === Image.Ready
                }
                Text {
                  anchors.centerIn: parent
                  visible: histImg.status !== Image.Ready
                  text: String(modelData.glyph || "").length > 0 ? modelData.glyph : "󰂚"
                  color: "white"
                  font.family: root.iconFont
                  font.pixelSize: 15
                }
              }
              Column {
                anchors.left: histIcon.right
                anchors.leftMargin: 10
                anchors.right: histTime.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text {
                  width: parent.width
                  text: String(modelData.summary || modelData.app || "")
                  color: "white"
                  font.family: root.textFont
                  font.weight: Font.DemiBold
                  font.pixelSize: 12
                  horizontalAlignment: Text.AlignLeft
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  visible: text.length > 0
                  text: String(modelData.body || "").replace(/<[^>]*>/g, "").replace(/\s+/g, " ")
                  color: Qt.rgba(1, 1, 1, 0.6)
                  font.family: root.textFont
                  font.pixelSize: 11
                  horizontalAlignment: Text.AlignLeft
                  elide: Text.ElideRight
                }
              }
              Text {
                id: histTime
                anchors.right: unseenDot.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: root.timeAgo(modelData.timestamp || 0)
                color: Qt.rgba(1, 1, 1, 0.45)
                font.family: root.textFont
                font.pixelSize: 10
              }
              Rectangle {
                id: unseenDot
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 7
                height: 7
                radius: 3.5
                color: root.accent
                opacity: parent.unseen ? 1 : 0
              }
              MouseArea {
                id: histMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openHistory(modelData)
              }
            }
          }
        }

        // The card shows five; say how many more there are and where they are.
        Text {
          visible: root.history.length > root.shownCount && !root.clearPending
          anchors.horizontalCenter: parent.horizontalCenter
          text: "+" + (root.history.length - root.shownCount) + " more in All"
          color: Qt.rgba(1, 1, 1, 0.55)
          font.family: root.textFont
          font.pixelSize: 11
          MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.expanded = false; Quickshell.execDetached(["omarchy-shell", "nasaq.notifcenter", "open"]) }
          }
        }
      }
    }
  }

  // MPRIS positions only move when asked for; tick while the card shows them.
  Timer {
    interval: 1000
    repeat: true
    running: root.expanded && root.playing
    onTriggered: if (root.player) root.player.positionChanged()
  }

  // ── Waveform (cava) ──────────────────────────────────────────────
  Process {
    id: cava
    running: root.playing
    command: ["bash", "-c",
      "cfg=$(mktemp); trap 'rm -f \"$cfg\"' EXIT; " +
      "printf '[general]\\nbars = 16\\nframerate = 30\\nsleep_timer = 1\\n[input]\\nmethod = pipewire\\n[output]\\nmethod = raw\\nraw_target = /dev/stdout\\ndata_format = ascii\\nascii_max_range = 100\\nbar_delimiter = 59\\nframe_delimiter = 10\\n[smoothing]\\nnoise_reduction = 60\\n' > \"$cfg\"; " +
      "cava -p \"$cfg\""]
    stdout: SplitParser {
      onRead: function(line) {
        var parts = String(line).split(";")
        var next = []
        for (var i = 0; i < 16; i++) next.push(parseInt(parts[i]) || 0)
        root.bars = next
      }
    }
    onRunningChanged: if (!running) root.bars = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  }

  // ── Prayer data ──────────────────────────────────────────────────
  FileView {
    id: configFile
    path: Quickshell.env("HOME") + "/.config/omarchy/nasaq/island.json"
    atomicWrites: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var c = JSON.parse(text())
        var merged = Object.assign({}, root.config, c)
        root.config = merged
        root.loadedDayKey = ""
        root.refreshPrayer()
      } catch (e) {}
    }
  }

  // Weather for the card: same Open-Meteo cache file as the desktop widgets,
  // so the two never ask twice. Refreshed with the prayer check and when the
  // card opens (the fetch itself only hits the network every 30 min).
  property var weather: null
  function refreshWeather() {
    if (weatherProc.running) return
    weatherProc.command = ["bash", "-c", Weather.fetchScript, "nasaq-weather", String(config.latitude), String(config.longitude)]
    weatherProc.running = true
  }
  Process {
    id: weatherProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { var w = Weather.parse(text); if (w) root.weather = w } }
  }
  Timer { interval: 30 * 60 * 1000; repeat: true; running: true; triggeredOnStart: true; onTriggered: root.refreshWeather() }

  function refreshPrayer() {
    var key = Island.gregorianKey(new Date())
    if (key === loadedDayKey && prayerDay) return
    if (prayerProc.running) return
    var d = new Date()
    prayerProc.command = ["bash", "-c",
      "cache=\"${XDG_CACHE_HOME:-$HOME/.cache}/nasaq-island\"; mkdir -p \"$cache\"; " +
      "f=\"$cache/prayer-$1-$2-$3-$4-$5.json\"; " +
      "if [ ! -s \"$f\" ]; then " +
      "curl -4 -sf --max-time 15 \"https://api.aladhan.com/v1/calendar/$1/$2?latitude=$3&longitude=$4&method=$5\" -o \"$f.tmp\" " +
      "&& jq -e '.code == 200' \"$f.tmp\" >/dev/null && mv \"$f.tmp\" \"$f\"; rm -f \"$f.tmp\"; fi; " +
      "cat \"$f\" 2>/dev/null",
      "nasaq-prayer", String(d.getFullYear()), String(d.getMonth() + 1),
      String(config.latitude), String(config.longitude), String(config.method)]
    prayerProc.running = true
  }

  Process {
    id: prayerProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var day = Island.dayFromMonth(text, new Date())
        if (day) {
          root.prayerDay = day
          root.loadedDayKey = Island.gregorianKey(new Date())
        }
      }
    }
  }

  // Midnight rollover, retries while offline, and prayer reminders.
  Timer {
    interval: 20000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      root.checkPrayerNow()
      root.refreshPrayer()
      var n = root.nextPrayer
      if (!n) return
      var mins = Math.round(root.msToNext / 60000)
      var tag = n.key + "@" + n.time.getTime()
      var remind = root.config.reminderMinutes || 5
      if (mins === remind && !root.notified[tag + ":pre"]) {
        root.notified[tag + ":pre"] = true
        root.showAlert(n.name + " بعد " + remind + " دقائق", "أذان " + n.name + " الساعة " + Island.formatTime(n.time), 8000)
      }
      // Remember the one that just passed so its moment can be announced.
      root.watchPrayer = n
    }
  }

  // Optional: 20 quiet minutes from the call to prayer — Do Not Disturb on
  // (handed back only if this turned it on) and whatever is playing paused.
  property bool quietOwned: false
  // The quiet window's end is kept in a state file, so a shell restart in the
  // middle of it (Fix Speakers restarts the shell) still hands DND back on time.
  readonly property string quietPath: Quickshell.env("HOME") + "/.local/state/nasaq/prayer-quiet"
  readonly property int quietMs: 20 * 60 * 1000
  function startQuiet() {
    quietOwned = root.notif.dnd !== true
    if (quietOwned) notifCall("setDnd", "on")
    Quickshell.execDetached(["playerctl", "pause"])
    quietFile.setText(JSON.stringify({ until: Date.now() + quietMs, owned: quietOwned }) + "\n")
    quietTimer.interval = quietMs
    quietTimer.restart()
  }
  function endQuiet() {
    if (root.quietOwned) root.notifCall("setDnd", "off")
    root.quietOwned = false
    quietFile.setText("")
  }
  Timer {
    id: quietTimer
    interval: root.quietMs
    onTriggered: root.endQuiet()
  }
  FileView {
    id: quietFile
    path: root.quietPath
    blockLoading: true
    printErrors: false
    onLoaded: {
      var o = null
      try { o = JSON.parse(String(text()).trim()) } catch (e) { return }
      if (!o || typeof o.until !== "number") return
      var left = o.until - Date.now()
      root.quietOwned = o.owned === true
      if (left > 0) { quietTimer.interval = left; quietTimer.restart() }
      else root.endQuiet()
    }
  }
  function setPrayerQuiet(on) {
    var c = Object.assign({}, root.config, { prayerQuiet: on })
    root.config = c
    configFile.setText(JSON.stringify(c, null, 2) + "\n")
  }

  property var watchPrayer: null
  onNowChanged: checkPrayerNow()
  // Also called by the 20 s timer before it moves watchPrayer on, so the
  // prayer that passed while the machine slept is not replaced unannounced.
  function checkPrayerNow() {
    var w = watchPrayer
    var t = Date.now()   // not `now`: right after a wake the clock may not have ticked yet
    if (!w || t < w.time.getTime()) return
    var tag = w.key + "@" + w.time.getTime() + ":now"
    watchPrayer = null
    // Up to ten minutes late still counts (the machine may have been asleep).
    if (notified[tag] || t - w.time.getTime() > 600000) return
    notified[tag] = true
    showAlert("حان الآن وقت صلاة " + w.name, root.config.city || "", 30000)
    if (root.config.prayerQuiet) startQuiet()
  }

  // ── Stock calendar on right-click ────────────────────────────────
  Loader {
    id: calendarLoader
    active: true
    visible: false
    source: "file:///usr/share/omarchy/shell/plugins/panels/clock/Panel.qml"
    onLoaded: {
      if ("bar" in item) item.bar = root.bar
      if ("settings" in item) item.settings = root.settings
      if ("anchorItem" in item) item.anchorItem = pill
      if ("hostWidget" in item) item.hostWidget = root
    }
  }
  onBarChanged: if (calendarLoader.item && "bar" in calendarLoader.item) calendarLoader.item.bar = root.bar

  // ── IPC ──────────────────────────────────────────────────────────
  // Takes over omarchy.osd's target, so every `omarchy osd` call lands here.
  IpcHandler {
    target: "osd"
    function show(payloadJson: string): string { root.showOsd(payloadJson); return "ok" }
    function close(): string { root.osdActive = false; return "ok" }
    function state(): string { return root.osdActive ? "open" : "closed" }
    function ping(): string { return "ok" }
  }

  IpcHandler {
    target: "nasaq.island"
    function expand(): string { root.expanded = true; return "ok" }
    function collapse(): string { root.expanded = false; return "ok" }
    function toggle(): string { root.expanded = !root.expanded; return "ok" }
    function alert(title: string, subtitle: string): string { root.showAlert(title, subtitle, 6000); return "ok" }
    // Same as the card's Clear button, committed at once.
    function clear(): string { root.clearPending = true; root.doClear(); return "ok" }
    function status(): string {
      return JSON.stringify({
        history: root.history.length, unseen: root.unseenCount, clearPending: root.clearPending,
        prayerLoaded: root.prayerDay !== null,
        next: root.nextPrayer ? { name: root.nextPrayer.key, at: Island.formatTime(root.nextPrayer.time) } : null,
        media: root.hasMedia, playing: root.playing
      })
    }
  }
}
