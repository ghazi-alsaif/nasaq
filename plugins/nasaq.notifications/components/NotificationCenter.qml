// NASAQ: Notification Center. A glass panel that slides in from
// the right with the date (and Hijri date), a month calendar, the weather,
// Do Not Disturb, and the notification history grouped by app.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.Commons
import "../NotificationLogic.js" as NotificationLogic
import "../../nasaq.island/Island.js" as Island
import "../../nasaq.island/Weather.js" as Weather
import "../../nasaq.commons" as Nasaq

Item {
  id: root

  property var service: null
  property bool open: false
  property bool shown: false

  readonly property string textFont: Nasaq.Theme.textFont
  readonly property string iconFont: Style.font.family
  readonly property color accent: Color.accent
  readonly property color cardColor: Nasaq.Theme.glass
  readonly property color tileColor: Qt.alpha(Color.foreground, 0.07)
  readonly property string home: Quickshell.env("HOME")

  property var entries: []
  property var weather: null
  property var prayerDay: null
  property var config: ({ city: "", latitude: 21.4225, longitude: 39.8262, method: 4 })
  property date viewMonth: new Date()
  property date now: new Date()

  property var expandedGroups: ({})
  function groupKey(e, i) {
    var key = e.app === "omarchy-action" ? "Omarchy" : (e.app || "Other")
    // NASAQ Settings > Notifications > Group by app (off = one card each)
    if (!Nasaq.Settings.get("notifications.groupByApp", true)) key = key + "\u0000" + (e.id || i)
    return key
  }
  readonly property var groups: {
    var order = [], map = {}
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      var key = groupKey(e, i)
      if (!map[key]) { map[key] = { app: key.split("\u0000")[0], key: key, icon: e.appIcon || (String(e.image || "").indexOf("image://icon/") === 0 ? String(e.image).slice(13) : ""), glyph: e.glyph || "", items: [] }; order.push(key) }
      map[key].items.push(e)
    }
    return order.map(function(k) { return map[k] })
  }

  readonly property var targetScreen: {
    var mon = Hyprland.focusedMonitor
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) if (mon && screens[i].name === mon.name) return screens[i]
    return screens.length > 0 ? screens[0] : null
  }

  function toggle() { open ? close() : show() }
  // Entries newer than this slide in when the list is rebuilt: a notification
  // that arrives while the panel is open. Set on show, so the opening list
  // doesn't animate every tile.
  property double listedAt: 0
  function show() {
    now = new Date()
    viewMonth = new Date()
    listedAt = Date.now()
    open = true
    reload()
    Qt.callLater(function() { root.shown = true })
  }
  function close() {
    shown = false
  }
  // One number drives the slide and the fade together (0 = in place, 1 = out),
  // so they can never drift apart; the window unmaps when it reaches 1.
  property real hideT: shown ? 0 : 1
  Behavior on hideT { Nasaq.NAnim { kind: root.shown ? "move" : "close" } }  // no overshoot on a large panel
  onHideTChanged: if (hideT >= 1 && !shown) open = false
  Timer { interval: 30000; running: root.open; repeat: true; onTriggered: root.now = new Date() }

  function reload() {
    if (service && !historyProc.running) {
      historyProc.command = ["bash", "-c", "awk 1 \"$1\"/*.json 2>/dev/null || true", "--", service.historyDir]
      historyProc.running = true
    }
    configView.reload()
  }

  function timeAgo(ts) {
    var diff = (Date.now() - ts) / 1000
    if (diff < 60) return "now"
    if (diff < 3600) return Math.floor(diff / 60) + "m"
    if (diff < 86400) return Math.floor(diff / 3600) + "h"
    if (diff < 172800) return "Yesterday"
    return Nasaq.Clock.dateShort(new Date(ts))
  }

  function iconFor(group) {
    var name = String(group.icon || "")
    if (name.indexOf("/") === 0) return "file://" + name
    if (name.indexOf("file://") === 0) return name
    if (name) return Quickshell.iconPath(name, true)
    var entry = DesktopEntries.heuristicLookup(group.app)
    return entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : ""
  }

  function clearGroup(group) {
    if (!service) return
    var files = group.items.map(function(e) { return service.historyDir + NotificationLogic.popupFileName(e) })
    Quickshell.execDetached(["rm", "-f"].concat(files))
    service.dismissPopupsMatching(group.items.map(function(e) { return e.originalId }).filter(function(x) { return x !== undefined && x !== null && x >= 0 }))
    // By key, not by identity: a delegate's modelData is a copy of the entry
    // (the Repeater hands out converted objects), so indexOf never matched
    // from the X or a swipe. The group then stayed in `entries`, its tile
    // grew back empty when `leaving` was cleared, and the reload cut it off.
    entries = entries.filter(function(e, i) { return groupKey(e, i) !== group.key })
    reloadTimer.restart()
  }

  function clearAll() {
    if (!service) return
    service.clearHistory()
    service.clearPopups()
    entries = []
    reloadTimer.restart()
  }

  // Exit motion. A group slides off to the side (the way it was swiped, or to
  // the right), fades and folds up at the same time so the groups below rise
  // with it, and is cleared once that is over. Clear all sends the groups off
  // one after another, top to bottom. With Motion off this is immediate.
  // leaving: group key -> "r" | "l"
  property var leaving: ({})
  function markLeaving(key, dir) {
    var l = Object.assign({}, leaving); l[key] = dir; leaving = l
  }
  function dismissGroup(group, dir) {
    if (!Nasaq.Motion.enabled || leaving[group.key]) { clearGroup(group); return }
    markLeaving(group.key, dir || "r")
    // Each group gets its own deadline: a second dismiss must not postpone the first.
    removeTimer.pending.push({ group: group, due: Date.now() + removeTimer.delay })
    if (!removeTimer.running) { removeTimer.interval = removeTimer.delay; removeTimer.start() }
  }
  Timer {
    id: removeTimer
    readonly property int delay: Nasaq.Motion.close + 10
    property var pending: []
    onTriggered: {
      var now = Date.now(), ready = [], rest = []
      pending.forEach(function(e) { (e.due <= now + 5 ? ready : rest).push(e) })
      pending = rest
      ready.forEach(function(e) { root.clearGroup(e.group) })
      var l = Object.assign({}, root.leaving)
      ready.forEach(function(e) { delete l[e.group.key] })
      root.leaving = l
      if (rest.length) { interval = Math.max(1, rest[0].due - now); start() }
    }
  }
  function clearAllCascade() {
    if (!Nasaq.Motion.enabled || groups.length === 0) { clearAll(); return }
    cascade.queue = groups.slice()
    cascadeEnd.keys = groups.map(function(g) { return g.key })
    cascade.restart()
  }
  Timer {
    id: cascade
    interval: 45
    repeat: true
    triggeredOnStart: true
    property var queue: []
    onTriggered: {
      if (queue.length === 0) { stop(); cascadeEnd.restart(); return }
      var g = queue.shift()
      root.markLeaving(g.key, "r")
    }
  }
  Timer {
    id: cascadeEnd
    interval: Nasaq.Motion.close + 10
    property var keys: []
    onTriggered: {
      root.clearAll()
      // Only this cascade's keys: a single dismiss still in flight keeps its own.
      var l = Object.assign({}, root.leaving)
      keys.forEach(function(k) { delete l[k] })
      root.leaving = l
    }
  }

  Timer { id: reloadTimer; interval: 400; onTriggered: root.reload() }
  // A notification filed while the panel is open: show it without a reopen.
  function refreshIfOpen() { if (open) reloadTimer.restart() }

  Process {
    id: historyProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var live = root.service ? root.service.liveRowsForReplay() : []
        var rows = NotificationLogic.historyRows(text, live, NotificationUrgency.Normal, 50)
        // Clear all deletes the files in a queued job; a reload that lands
        // before it would bring the cleared entries back for a moment.
        var clearedAt = root.service ? Number(root.service.historyClearedAt) || 0 : 0
        root.entries = rows.filter(function(e) { return (e.timestamp || 0) > clearedAt })
        root.listedAt = Date.now()
      }
    }
  }

  FileView {
    id: configView
    path: root.home + "/.config/omarchy/nasaq/island.json"
    printErrors: false
    onLoaded: {
      try { root.config = Object.assign({}, root.config, JSON.parse(text())) } catch (e) {}
      weatherProc.command = ["bash", "-c", Weather.fetchScript, "nasaq-weather", String(root.config.latitude), String(root.config.longitude)]
      weatherProc.running = true
      var d = new Date()
      prayerProc.command = ["bash", "-c", "cat \"${XDG_CACHE_HOME:-$HOME/.cache}/nasaq-island/prayer-$1-$2-$3-$4-$5.json\" 2>/dev/null",
        "nasaq-prayer", String(d.getFullYear()), String(d.getMonth() + 1), String(root.config.latitude), String(root.config.longitude), String(root.config.method || 4)]
      prayerProc.running = true
    }
  }
  Process {
    id: weatherProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { var w = Weather.parse(text); if (w) root.weather = w } }
  }
  Process {
    id: prayerProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { var p = Island.dayFromMonth(text, new Date()); if (p) root.prayerDay = p } }
  }

  // ── UI ───────────────────────────────────────────────────────────
  component Tile: Rectangle {
    radius: 16
    color: root.tileColor
    border.color: Qt.alpha(Color.foreground, 0.05)
    border.width: 1
  }

  PanelWindow {
    id: win
    screen: root.targetScreen
    visible: root.open
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nasaq-notification-center"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    readonly property real topGap: root.service ? root.service.barClearance : 40

    MouseArea { anchors.fill: parent; onClicked: root.close() }
    Item { anchors.fill: parent; focus: root.open; Keys.onEscapePressed: root.close() }

    Rectangle {
      id: panel
      width: 380
      y: win.topGap
      // Anchored to the right edge and slid by its own (fixed) width, so the
      // hidden position is right from the first frame: win.width is 0 before
      // the window is mapped, and an x based on it made the first open sweep
      // in from the left.
      anchors.right: parent.right
      anchors.rightMargin: Style.gapsOut + 4
      transform: Translate {
        x: root.hideT * (panel.width + Style.gapsOut + 24)
      }
      height: Math.min(content.implicitHeight + 28, win.height - win.topGap - Style.gapsOut - 4)
      radius: Nasaq.Theme.radiusPanel
      color: root.cardColor
      border.color: Qt.alpha(Color.foreground, 0.14)
      border.width: 1
      clip: true
      // Solid both ways: the panel slides fully off screen, so it needs no
      // fade (a fade on the slow-starting close curve read as the panel
      // dissolving on the way out, unlike the solid slide in).
      opacity: root.hideT >= 1 ? 0 : 1

      MouseArea { anchors.fill: parent }

      Flickable {
        anchors.fill: parent
        anchors.margins: 14
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: content
          width: parent.width
          spacing: 12

          // ── Date header ──
          Item {
            width: parent.width
            height: 54
            Column {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              Text {
                text: Nasaq.Clock.weekday(root.now)
                color: root.accent
                font.family: root.textFont
                font.weight: Font.DemiBold
                font.pixelSize: 13
              }
              Text {
                text: Nasaq.Clock.dayMonth(root.now)
                color: Color.foreground
                font.family: root.textFont
                font.weight: Font.Bold
                font.pixelSize: 24
              }
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: root.prayerDay !== null && Nasaq.Settings.get("island.hijri", "both") !== "gregorian"
              text: root.prayerDay ? Nasaq.Clock.hijri(root.prayerDay.hijri) : ""
              color: Qt.alpha(Color.foreground, 0.6)
              font.family: root.textFont
              font.pixelSize: 13
            }
          }

          // ── Calendar ──
          Tile {
            width: parent.width
            height: cal.implicitHeight + 24
            Column {
              id: cal
              x: 12
              y: 12
              width: parent.width - 24
              spacing: 6

              readonly property int year: root.viewMonth.getFullYear()
              readonly property int month: root.viewMonth.getMonth()
              readonly property int firstDow: new Date(year, month, 1).getDay()
              readonly property int days: new Date(year, month + 1, 0).getDate()

              Item {
                width: parent.width
                height: 22
                Text {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: Nasaq.Clock.monthYear(root.viewMonth)
                  color: Color.foreground
                  font.family: root.textFont
                  font.weight: Font.DemiBold
                  font.pixelSize: 14
                }
                Row {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 14
                  Repeater {
                    model: [{ g: "󰅁", d: -1 }, { g: "󰅂", d: 1 }]
                    delegate: Text {
                      required property var modelData
                      text: modelData.g
                      color: navMouse.containsMouse ? Color.foreground : Qt.alpha(Color.foreground, 0.6)
                      font.family: root.iconFont
                      font.pixelSize: 14
                      MouseArea {
                        id: navMouse
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.viewMonth = new Date(cal.year, cal.month + modelData.d, 1)
                      }
                    }
                  }
                }
              }

              Grid {
                columns: 7
                width: parent.width
                readonly property real cell: width / 7
                Repeater {
                  model: ["S", "M", "T", "W", "T", "F", "S"]
                  delegate: Text {
                    required property string modelData
                    width: parent.cell
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: Qt.alpha(Color.foreground, 0.45)
                    font.family: root.textFont
                    font.weight: Font.DemiBold
                    font.pixelSize: 11
                  }
                }
                Repeater {
                  model: 42
                  delegate: Item {
                    required property int index
                    readonly property int day: index - cal.firstDow + 1
                    readonly property bool inMonth: day >= 1 && day <= cal.days
                    readonly property bool today: inMonth && day === root.now.getDate()
                      && cal.month === root.now.getMonth() && cal.year === root.now.getFullYear()
                    width: parent.cell
                    height: 28
                    visible: index < 35 || cal.firstDow + cal.days > 35
                    Rectangle {
                      anchors.centerIn: parent
                      width: 26
                      height: 26
                      radius: 13
                      color: parent.today ? root.accent : "transparent"
                    }
                    Text {
                      anchors.centerIn: parent
                      text: parent.inMonth ? parent.day : ""
                      color: parent.today ? Color.foreground : ((index % 7 === 5 || index % 7 === 6) ? Qt.alpha(Color.foreground, 0.55) : Qt.alpha(Color.foreground, 0.9))
                      font.family: root.textFont
                      font.weight: parent.today ? Font.Bold : Font.Normal
                      font.pixelSize: 12
                    }
                  }
                }
              }
            }
          }

          // ── Weather ──
          Tile {
            width: parent.width
            height: 118
            visible: root.weather !== null
            Item {
              anchors.fill: parent
              anchors.margins: 12
              Column {
                anchors.left: parent.left
                anchors.top: parent.top
                Text {
                  text: root.config.city || ""
                  color: Color.foreground
                  font.family: root.textFont
                  font.weight: Font.DemiBold
                  font.pixelSize: 13
                }
                Text {
                  text: root.weather ? root.weather.temp + "°" : ""
                  color: Color.foreground
                  font.family: root.textFont
                  font.weight: Font.Light
                  font.pixelSize: 34
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
                  font.pixelSize: 26
                }
                Text {
                  anchors.right: parent.right
                  text: root.weather ? root.weather.label + " · 󰖎 " + root.weather.humidity + "%" : ""
                  color: Qt.alpha(Color.foreground, 0.65)
                  font.family: root.textFont
                  font.pixelSize: 11
                }
              }
              Row {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                Repeater {
                  model: root.weather ? root.weather.days : []
                  delegate: Column {
                    required property var modelData
                    width: parent.width / 5
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: modelData.name
                      color: Qt.alpha(Color.foreground, 0.55)
                      font.family: root.textFont
                      font.pixelSize: 10
                    }
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: modelData.icon + " " + modelData.max + "°"
                      color: Color.foreground
                      font.family: root.iconFont
                      font.pixelSize: 12
                    }
                  }
                }
              }
            }
          }

          // ── Do Not Disturb ──
          Tile {
            width: parent.width
            height: 46
            Text {
              id: dndIcon
              anchors.left: parent.left
              anchors.leftMargin: 14
              anchors.verticalCenter: parent.verticalCenter
              text: "󰽥"
              color: root.service && root.service.doNotDisturb ? Color.accent : Qt.alpha(Color.foreground, 0.7)
              font.family: root.iconFont
              font.pixelSize: 17
            }
            Text {
              anchors.left: dndIcon.right
              anchors.leftMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              text: "Do Not Disturb"
              color: Color.foreground
              font.family: root.textFont
              font.weight: Font.DemiBold
              font.pixelSize: 13
            }
            Rectangle {
              id: sw
              readonly property bool checked: !!root.service && root.service.doNotDisturb
              anchors.right: parent.right
              anchors.rightMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              width: 38
              height: 22
              radius: 11
              color: checked ? Color.accent : Qt.alpha(Color.foreground, 0.22)
              Behavior on color { Nasaq.NColour { duration: Nasaq.Motion.micro } }
              Rectangle {
                width: 18
                height: 18
                radius: 9
                y: 2
                x: sw.checked ? sw.width - width - 2 : 2
                color: Color.foreground
                Behavior on x { Nasaq.NAnim { kind: "fast" } }
              }
              MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.service) root.service.setDoNotDisturb(!root.service.doNotDisturb)
              }
            }
          }

          // ── Notifications ──
          Item {
            width: parent.width
            height: 22
            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Notifications"
              color: Color.foreground
              font.family: root.textFont
              font.weight: Font.Bold
              font.pixelSize: 15
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: root.entries.length > 0
              text: "Clear All"
              color: clearAllMouse.containsMouse ? Color.foreground : root.accent
              font.family: root.textFont
              font.weight: Font.DemiBold
              font.pixelSize: 12
              MouseArea {
                id: clearAllMouse
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.clearAllCascade()
              }
            }
          }

          Text {
            visible: root.entries.length === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            topPadding: 10
            bottomPadding: 14
            text: "No Notifications"
            color: Qt.alpha(Color.foreground, 0.4)
            font.family: root.textFont
            font.pixelSize: 13
          }

          Repeater {
            model: root.groups
            delegate: Tile {
              id: groupTile
              required property var modelData
              width: content.width

              // Swipe sideways to clear the group: it follows the pointer and
              // springs back if let go early; past a third of its width it
              // carries on out from where it was let go. Clear all and the X
              // send it the same way. It folds up (height to 0) as it goes, so
              // the groups below rise instead of jumping.
              readonly property string out: root.leaving[modelData.key] || ""
              property real dragX: 0
              property real fade: 0
              // A new arrival grows into its place (0 → 1) while it slides in, so
              // the groups below it glide down instead of jumping.
              property real grow: 1
              x: dragX
              opacity: (1 - fade) * (1 - Math.min(0.5, Math.abs(dragX) / Math.max(1, width)))
              height: out ? 0 : (groupCol.implicitHeight + 20) * grow
              clip: true
              // The height animates only once the tile is settled: the tiles
              // are rebuilt after a clear, and a new one must not grow in from
              // 0. (Gating on `out` itself raced the height binding.)
              property bool settled: false
              // Leaving folds on the same length and curve as the slide out, so the
              // tile arrives at nothing in one motion; other height changes move in place.
              Behavior on height { enabled: groupTile.settled; Nasaq.NAnim { kind: groupTile.out ? "close" : "move" } }
              onOutChanged: if (out === "r" || out === "l") leave(out === "r")
              // Arrived while the panel was open: slide in from the right.
              Component.onCompleted: {
                Qt.callLater(function() { groupTile.settled = true })
                var ts = modelData.items.length ? Number(modelData.items[0].timestamp) || 0 : 0
                if (Nasaq.Motion.enabled && !out && ts > root.listedAt) { dragX = 28; fade = 1; grow = 0; enterAnim.start() }
              }
              ParallelAnimation {
                id: enterAnim
                NumberAnimation { target: groupTile; property: "dragX"; to: 0; duration: Nasaq.Motion.open; easing.type: Easing.BezierSpline; easing.bezierCurve: Nasaq.Motion.enter }
                NumberAnimation { target: groupTile; property: "fade"; to: 0; duration: Nasaq.Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Nasaq.Motion.decel }
                NumberAnimation { target: groupTile; property: "grow"; to: 1; duration: Nasaq.Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Nasaq.Motion.standard }
              }
              function leave(right) {
                backAnim.stop(); exitAnim.stop()
                exitX.to = right ? width + 24 : -(width + 24)
                exitAnim.start()
              }
              ParallelAnimation {
                id: exitAnim
                NumberAnimation { id: exitX; target: groupTile; property: "dragX"; duration: Nasaq.Motion.close; easing.type: Easing.BezierSpline; easing.bezierCurve: Nasaq.Motion.exit }
                NumberAnimation { target: groupTile; property: "fade"; to: 1; duration: Nasaq.Motion.close; easing.type: Easing.BezierSpline; easing.bezierCurve: Nasaq.Motion.decel }
              }
              NumberAnimation { id: backAnim; target: groupTile; property: "dragX"; to: 0; duration: Nasaq.Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Nasaq.Motion.decel }
              DragHandler {
                id: swipe
                target: null
                enabled: !groupTile.out
                xAxis.enabled: true
                yAxis.enabled: false
                onTranslationChanged: if (active) { backAnim.stop(); groupTile.dragX = translation.x }
                onActiveChanged: {
                  if (active) return
                  if (Math.abs(groupTile.dragX) > groupTile.width / 3) root.dismissGroup(groupTile.modelData, groupTile.dragX > 0 ? "r" : "l")
                  else backAnim.restart()
                }
              }

              Column {
                id: groupCol
                x: 12
                y: 10
                width: parent.width - 24
                spacing: 8

                Item {
                  width: parent.width
                  height: 22
                  IconImage {
                    id: appIconImg
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: 18
                    source: root.iconFor(groupTile.modelData)
                    visible: source != ""
                  }
                  Text {
                    id: glyphIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !appIconImg.visible
                    text: groupTile.modelData.glyph || "󰂚"
                    color: Qt.alpha(Color.foreground, 0.75)
                    font.family: root.iconFont
                    font.pixelSize: 15
                  }
                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 26
                    anchors.verticalCenter: parent.verticalCenter
                    text: groupTile.modelData.app + (groupTile.modelData.items.length > 1 ? "  ·  " + groupTile.modelData.items.length : "")
                    color: Qt.alpha(Color.foreground, 0.7)
                    font.family: root.textFont
                    font.weight: Font.DemiBold
                    font.pixelSize: 12
                  }
                  Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰅖"
                    color: groupClose.containsMouse ? Color.foreground : Qt.alpha(Color.foreground, 0.45)
                    font.family: root.iconFont
                    font.pixelSize: 13
                    MouseArea {
                      id: groupClose
                      anchors.fill: parent
                      anchors.margins: -6
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.dismissGroup(groupTile.modelData, "r")
                    }
                  }
                }

                Repeater {
                  model: root.expandedGroups[groupTile.modelData.key] ? groupTile.modelData.items : groupTile.modelData.items.slice(0, 4)
                  delegate: Item {
                    required property var modelData
                    width: groupCol.width
                    height: entryCol.implicitHeight
                    Column {
                      id: entryCol
                      width: parent.width - 50
                      spacing: 1
                      Text {
                        width: parent.width
                        text: modelData.summary || ""
                        color: Color.foreground
                        elide: Text.ElideRight
                        font.family: root.textFont
                        font.weight: Font.DemiBold
                        font.pixelSize: 13
                      }
                      Text {
                        width: parent.width
                        visible: text.length > 0
                        text: String(modelData.body || "").replace(/<[^>]*>/g, "")
                        color: Qt.alpha(Color.foreground, 0.65)
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font.family: root.textFont
                        font.pixelSize: 12
                      }
                    }
                    Text {
                      anchors.right: parent.right
                      anchors.top: parent.top
                      text: root.timeAgo(modelData.timestamp || 0)
                      color: Qt.alpha(Color.foreground, 0.45)
                      font.family: root.textFont
                      font.pixelSize: 11
                    }
                  }
                }

                Text {
                  readonly property bool isOpen: !!root.expandedGroups[groupTile.modelData.key]
                  visible: groupTile.modelData.items.length > 4
                  text: isOpen ? "Show less" : "+" + (groupTile.modelData.items.length - 4) + " more"
                  color: moreMouse.containsMouse ? Color.foreground : Qt.alpha(Color.foreground, 0.45)
                  font.family: root.textFont
                  font.pixelSize: 11
                  MouseArea {
                    id: moreMouse
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { var m = Object.assign({}, root.expandedGroups); m[groupTile.modelData.key] = !parent.isOpen; root.expandedGroups = m }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
