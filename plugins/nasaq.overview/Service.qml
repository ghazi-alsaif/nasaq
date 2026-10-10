import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.Commons

// NASAQ: macOS Mission Control for Hyprland.
//
// `omarchy-shell nasaq.overview toggle` blurs the screen, flies the current
// workspace's windows (live previews) from where they sit into a grid, and
// lines every workspace up in a strip along the top. Click a window to focus
// it, click a workspace to go there, drag a window onto a workspace to move
// it. Keys: arrows + Enter, 1-9 for workspaces, Esc to leave.
Item {
  id: root

  property var shell: null
  property string omarchyPath: ""

  property bool open: false      // overlay mapped
  property bool shown: false     // windows in their grid spots (drives animation)
  property int selected: 0
  readonly property string textFont: "IBM Plex Sans Arabic"

  readonly property var focusedMonitor: Hyprland.focusedMonitor
  readonly property var targetScreen: {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (focusedMonitor && screens[i].name === focusedMonitor.name) return screens[i]
    return screens.length > 0 ? screens[0] : null
  }
  readonly property var monitorInfo: focusedMonitor ? focusedMonitor.lastIpcObject : null
  readonly property real monX: monitorInfo ? monitorInfo.x : 0
  readonly property real monY: monitorInfo ? monitorInfo.y : 0
  readonly property real monScale: monitorInfo && monitorInfo.scale ? monitorInfo.scale : 1

  // Heavy screens (more than 1.5× the pixels of 1080p, or a fractional scale —
  // e.g. the iMac's 4K at 1.6) take the GPU-light path: window cards keep
  // their final size and animate with a transform (no per-frame re-render of
  // the rounded mask), and live previews pause while the open/close animation
  // runs. 1080p at scale 1 (the laptop) keeps the original path untouched.
  // Override: ~/.config/omarchy/nasaq/overview.json {"lite": true|false}.
  property var liteOverride: null
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/nasaq/overview.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { var v = JSON.parse(text()).lite; root.liteOverride = (v === true || v === false) ? v : null } catch (e) { root.liteOverride = null } }
    onLoadFailed: root.liteOverride = null
  }
  readonly property bool heavy: {
    if (liteOverride !== null) return liteOverride
    var w = monitorInfo ? monitorInfo.width : 1920, h = monitorInfo ? monitorInfo.height : 1080
    return w * h > 1920 * 1080 * 1.5 || Math.abs(monScale - Math.round(monScale)) > 0.01
  }
  // True once the opening animation has finished; previews go live then.
  property bool settled: false
  Timer { id: settleTimer; interval: 320; onTriggered: root.settled = true }
  readonly property int activeWsId: focusedMonitor && focusedMonitor.activeWorkspace ? focusedMonitor.activeWorkspace.id : 1

  readonly property var allToplevels: Hyprland.toplevels ? Hyprland.toplevels.values : []
  function windowsOn(wsId) {
    var out = []
    for (var i = 0; i < allToplevels.length; i++) {
      var t = allToplevels[i]
      var ipc = t ? t.lastIpcObject : null
      if (!ipc || !ipc.workspace || ipc.workspace.id !== wsId || !ipc.mapped || ipc.hidden) continue
      out.push(t)
    }
    return out
  }
  readonly property var currentWindows: windowsOn(activeWsId)
  readonly property var workspaceIds: {
    var ids = []
    var ws = Hyprland.workspaces ? Hyprland.workspaces.values : []
    for (var i = 0; i < ws.length; i++) {
      var w = ws[i]
      if (!w || w.id <= 0) continue
      if (focusedMonitor && w.monitor && w.monitor.name !== focusedMonitor.name) continue
      ids.push(w.id)
    }
    if (ids.indexOf(activeWsId) === -1) ids.push(activeWsId)
    // Workspace 1 always shows, even empty (Hyprland drops empty workspaces).
    if (ids.indexOf(1) === -1) ids.push(1)
    ids.sort(function(a, b) { return a - b })
    var next = 1
    while (ids.indexOf(next) !== -1) next++
    ids.push(next)   // empty "new desktop" slot
    return ids
  }

  function toggle() { open ? close() : show() }

  // Window edges follow the window settings: rounding and border width from
  // the control center (~/.config/omarchy/nasaq/windows.json, live), border
  // colours from Hyprland's theme borders (read on every open).
  property var look: ({})
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/nasaq/windows.json"
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { root.look = JSON.parse(text()) } catch (e) {} }
  }
  readonly property int edgeRounding: Math.round(look.rounding !== undefined ? look.rounding : 14)
  readonly property int edgeBorder: Math.round(look.border !== undefined ? look.border : 2)
  property var activeBorder: ({ colors: ["#ee5e7d92", "#eef6cc78"], angle: 45 })
  property var inactiveBorder: ({ colors: ["#aa2a3140"], angle: 0 })
  // "ee5e7d92 eef6cc78 45deg" → { colors: ["#ee5e7d92", …], angle: 45 }
  function parseBorder(css) {
    var out = { colors: [], angle: 0 }
    String(css || "").trim().split(/\s+/).forEach(function(t) {
      if (/deg$/.test(t)) out.angle = parseFloat(t) || 0
      else if (/^[0-9a-fA-F]{8}$/.test(t)) out.colors.push("#" + t)
    })
    return out
  }
  Process {
    id: borderProc
    command: ["bash", "-c", "hyprctl getoption general:col.active_border -j | jq -r .gradient; hyprctl getoption general:col.inactive_border -j | jq -r .gradient"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        var a = root.parseBorder(lines[0]), i = root.parseBorder(lines[1])
        if (a.colors.length) root.activeBorder = a
        if (i.colors.length) root.inactiveBorder = i
      }
    }
  }

  // Opens at once: no screen grab first (it took ~0.6 s at 4K). Every
  // workspace thumbnail, the current one included, is live window previews
  // over the wallpaper.
  function show() {
    if (open) return
    Hyprland.refreshToplevels()
    Hyprland.refreshWorkspaces()
    Hyprland.refreshMonitors()
    if (!borderProc.running) borderProc.running = true
    reveal()
  }

  function reveal() {
    selected = 0
    settled = false
    settleTimer.restart()
    open = true
    Qt.callLater(function() { root.shown = true })
  }

  function close() {
    if (!open) return
    settleTimer.stop()
    settled = false
    shown = false
    hideTimer.restart()
  }

  function dispatch(expr) {
    Quickshell.execDetached(["hyprctl", "dispatch", expr])
  }

  function focusWindow(t) {
    if (!t) return
    var addr = "0x" + String(t.address).replace(/^0x/, "")
    dispatch('hl.dsp.focus({ window = "address:' + addr + '" })')
    close()
  }

  function goToWorkspace(id) {
    dispatch('hl.dsp.focus({ workspace = "' + id + '" })')
    close()
  }

  function moveWindow(t, wsId) {
    if (!t || wsId === activeWsId) return
    var addr = "0x" + String(t.address).replace(/^0x/, "")
    dispatch('hl.dsp.focus({ window = "address:' + addr + '" })')
    moveTimer.expr = 'hl.dsp.window.move({ workspace = "' + wsId + '", follow = false })'
    moveTimer.restart()
  }

  Timer {
    id: moveTimer
    interval: 60
    property string expr: ""
    onTriggered: {
      root.dispatch(expr)
      refreshTimer.restart()
    }
  }
  Timer { id: refreshTimer; interval: 150; onTriggered: { Hyprland.refreshToplevels(); Hyprland.refreshWorkspaces() } }
  // Closing plays the opening in reverse (same durations, mirrored easing),
  // so the overlay stays until the longest animation (300 ms) has finished.
  Timer { id: hideTimer; interval: 300; onTriggered: root.open = false }


  IpcHandler {
    target: "nasaq.overview"
    function toggle(): string { root.toggle(); return "ok" }
    function open(): string { root.show(); return "ok" }
    function close(): string { root.close(); return "ok" }
    function status(): string { return JSON.stringify({ heavy: root.heavy, scale: root.monScale, settled: root.settled }) }
  }

  function appIcon(t) {
    var cls = t && t.lastIpcObject ? String(t.lastIpcObject.class || "") : ""
    var entry = cls ? DesktopEntries.heuristicLookup(cls) : null
    return entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : ""
  }

  // Grid slots for the current workspace's windows, in overlay coordinates.
  function gridRects(count, area) {
    var rects = []
    if (count === 0) return rects
    var cols = Math.ceil(Math.sqrt(count * area.width / area.height / 1.6))
    cols = Math.max(1, Math.min(count, cols))
    var rows = Math.ceil(count / cols)
    var gap = 36
    var cw = (area.width - gap * (cols - 1)) / cols
    var ch = (area.height - gap * (rows - 1)) / rows
    for (var i = 0; i < count; i++) {
      var r = Math.floor(i / cols), c = i % cols
      var inRow = r === rows - 1 ? count - r * cols : cols
      var rowOffset = (cols - inRow) * (cw + gap) / 2
      rects.push({ x: area.x + rowOffset + c * (cw + gap), y: area.y + r * (ch + gap), w: cw, h: ch })
    }
    return rects
  }

  PanelWindow {
    id: overlay
    screen: root.targetScreen
    visible: root.open
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nasaq-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property real stripH: Math.round(height * 0.16)
    readonly property rect gridArea: Qt.rect(width * 0.08, stripH + 70, width * 0.84, height - stripH - 120)
    readonly property var rects: root.gridRects(root.currentWindows.length, gridArea)
    readonly property real sx: width / ((root.targetScreen ? root.targetScreen.width : width))

    Item {
      anchors.fill: parent
      focus: root.open
      Keys.onPressed: function(e) {
        var n = root.currentWindows.length
        if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true }
        else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && n > 0) { root.focusWindow(root.currentWindows[root.selected]); e.accepted = true }
        else if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab) { root.selected = n ? (root.selected + 1) % n : 0; e.accepted = true }
        else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab) { root.selected = n ? (root.selected - 1 + n) % n : 0; e.accepted = true }
        else if ((e.key === Qt.Key_Down || e.key === Qt.Key_Up) && n > 0) {
          // The cards sit in a grid: one row = the cards sharing the first card's y.
          var cols = 0
          for (var i = 0; i < overlay.rects.length; i++) if (overlay.rects[i].y === overlay.rects[0].y) cols++
          var next = root.selected + (e.key === Qt.Key_Down ? cols : -cols)
          // Down from a full row into a shorter last row lands on its last card.
          if (next >= n && cols > 0 && Math.floor(root.selected / cols) < Math.ceil(n / cols) - 1) next = n - 1
          if (next >= 0 && next < n) root.selected = next
          e.accepted = true
        }
        else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) { root.goToWorkspace(e.key - Qt.Key_0); e.accepted = true }
      }
    }

    // Backdrop: none drawn here. Hyprland blurs behind this layer itself
    // (layer rule for "nasaq-overview" in looknfeel.lua, xray so only the
    // wallpaper shows), with exactly the windows' blur settings.
    // The wallpaper image below only feeds the workspace thumbnails.
    Image {
      id: backdrop
      anchors.fill: parent
      source: "file://" + Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
      sourceSize.width: Math.round(overlay.width / 2)
      sourceSize.height: Math.round(overlay.height / 2)
      fillMode: Image.PreserveAspectCrop
      // Loaded once and kept: the wallpaper is a 5K PNG, too slow to decode
      // on every open.
      asynchronous: true
      visible: false
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    // ── Workspace strip ──
    Row {
      id: strip
      anchors.horizontalCenter: parent.horizontalCenter
      y: root.shown ? 26 : -overlay.stripH
      spacing: 18
      opacity: root.shown ? 1 : 0
      Behavior on y { NumberAnimation { duration: 260; easing.type: root.shown ? Easing.OutCubic : Easing.InCubic } }
      Behavior on opacity { NumberAnimation { duration: 200 } }

      Repeater {
        model: root.workspaceIds
        delegate: Column {
          id: wsDelegate
          required property int modelData
          required property int index
          readonly property bool isActive: modelData === root.activeWsId
          readonly property bool isNew: index === root.workspaceIds.length - 1
          readonly property var wins: root.open ? root.windowsOn(modelData) : []
          property bool dropHover: false
          spacing: 6

          Rectangle {
            id: thumb
            objectName: "wsThumb"
            property int wsId: wsDelegate.modelData
            width: Math.round(overlay.stripH * overlay.width / overlay.height)
            height: overlay.stripH
            radius: 10
            color: wsDelegate.isNew ? Qt.rgba(1, 1, 1, 0.08) : "#111"
            border.width: wsDelegate.isActive || wsDelegate.dropHover ? 2 : 1
            border.color: wsDelegate.dropHover ? "white" : wsDelegate.isActive ? Color.accent : Qt.rgba(1, 1, 1, 0.18)
            clip: true
            scale: thumbMouse.containsMouse || wsDelegate.dropHover ? 1.04 : 1
            Behavior on scale { NumberAnimation { duration: 120 } }

            Image {
              anchors.fill: parent
              visible: !wsDelegate.isNew
              source: backdrop.source
              sourceSize: backdrop.sourceSize
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
            }

            Repeater {
              model: wsDelegate.wins
              delegate: ScreencopyView {
                required property var modelData
                readonly property var ipc: modelData.lastIpcObject
                readonly property real k: thumb.width / (root.targetScreen ? root.targetScreen.width : 1)
                x: ((ipc.at[0] - root.monX) / root.monScale) * k
                y: ((ipc.at[1] - root.monY) / root.monScale) * k
                width: ipc.size[0] / root.monScale * k
                height: ipc.size[1] / root.monScale * k
                captureSource: root.open && modelData.wayland ? modelData.wayland : null
                live: false
              }
            }

            Text {
              anchors.centerIn: parent
              visible: wsDelegate.isNew
              text: "+"
              color: Qt.rgba(1, 1, 1, 0.6)
              font.pixelSize: 28
            }

            MouseArea {
              id: thumbMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToWorkspace(wsDelegate.modelData)
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: wsDelegate.isNew ? "New" : "Desktop " + wsDelegate.modelData
            color: wsDelegate.isActive ? "white" : Qt.rgba(1, 1, 1, 0.6)
            font.family: root.textFont
            font.pixelSize: 12
            font.weight: wsDelegate.isActive ? Font.DemiBold : Font.Normal
          }
        }
      }
    }

    // ── Current workspace windows ──
    Repeater {
      id: windowRepeater
      model: root.open ? root.currentWindows : []
      delegate: Item {
        id: win
        required property var modelData
        required property int index
        readonly property var ipc: modelData.lastIpcObject
        readonly property real realX: (ipc.at[0] - root.monX) / root.monScale * overlay.sx
        readonly property real realY: (ipc.at[1] - root.monY) / root.monScale * overlay.sx
        readonly property real realW: ipc.size[0] / root.monScale * overlay.sx
        readonly property real realH: ipc.size[1] / root.monScale * overlay.sx
        readonly property var slot: overlay.rects[index] || { x: realX, y: realY, w: realW, h: realH }
        readonly property real fit: Math.min(1, slot.w / realW, (slot.h - 30) / realH)
        readonly property real gridW: realW * fit
        readonly property real gridH: realH * fit
        readonly property bool hot: winMouse.containsMouse || root.selected === index
        property bool dragging: false

        readonly property real targetX: root.shown ? slot.x + (slot.w - gridW) / 2 : realX
        readonly property real targetY: root.shown ? slot.y + (slot.h - 30 - gridH) / 2 : realY
        x: targetX
        y: targetY
        // Heavy screens: the card is always laid out at its grid size and
        // the real-window size is reached with a scale transform instead.
        width: root.heavy || root.shown ? gridW : realW
        height: (root.heavy || root.shown ? gridH : realH) + 30
        z: dragging ? 10 : 1
        transform: Scale {
          origin.x: 0
          origin.y: 0
          xScale: root.heavy && !root.shown && win.gridW > 0 ? win.realW / win.gridW : 1
          yScale: root.heavy && !root.shown && win.gridH > 0 ? (win.realH + 30) / (win.gridH + 30) : 1
          Behavior on xScale { enabled: root.heavy; NumberAnimation { duration: 300; easing.type: root.shown ? Easing.OutCubic : Easing.InCubic } }
          Behavior on yScale { enabled: root.heavy; NumberAnimation { duration: 300; easing.type: root.shown ? Easing.OutCubic : Easing.InCubic } }
        }
        Behavior on x { enabled: !win.dragging; NumberAnimation { duration: 300; easing.type: root.shown ? Easing.OutCubic : Easing.InCubic } }
        Behavior on y { enabled: !win.dragging; NumberAnimation { duration: 300; easing.type: root.shown ? Easing.OutCubic : Easing.InCubic } }
        Behavior on width { enabled: !root.heavy; NumberAnimation { duration: 300; easing.type: root.shown ? Easing.OutCubic : Easing.InCubic } }
        Behavior on height { enabled: !root.heavy; NumberAnimation { duration: 300; easing.type: root.shown ? Easing.OutCubic : Easing.InCubic } }

        // Same edges as the real window: rounding + border from the window
        // settings, theme border colours (active gradient for the focused or
        // hovered window, inactive colour for the rest).
        Item {
          id: frame
          width: parent.width
          height: parent.height - 30
          scale: win.dragging ? 0.6 : (win.hot && root.shown ? 1.03 : 1)
          Behavior on scale { NumberAnimation { duration: 140 } }
          readonly property var edge: win.hot || Hyprland.activeToplevel === win.modelData ? root.activeBorder : root.inactiveBorder
          readonly property real bw: root.edgeBorder
          readonly property real rad: Math.min(root.edgeRounding, width / 2, height / 2)

          Shape {
            anchors.fill: parent
            visible: frame.bw > 0
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
              strokeWidth: -1
              fillGradient: LinearGradient {
                readonly property real a: frame.edge.angle * Math.PI / 180
                x1: frame.width / 2 - Math.cos(a) * frame.width / 2
                y1: frame.height / 2 + Math.sin(a) * frame.height / 2
                x2: frame.width / 2 + Math.cos(a) * frame.width / 2
                y2: frame.height / 2 - Math.sin(a) * frame.height / 2
                GradientStop { position: 0; color: frame.edge.colors[0] }
                GradientStop { position: 1; color: frame.edge.colors[frame.edge.colors.length - 1] }
              }
              PathRectangle { x: 0; y: 0; width: frame.width; height: frame.height; radius: frame.rad }
            }
          }

          Item {
            id: content
            anchors.fill: parent
            anchors.margins: frame.bw
            ScreencopyView {
              id: shot
              anchors.fill: parent
              captureSource: root.open && win.modelData.wayland ? win.modelData.wayland : null
              // Heavy screens: one frame while animating, live once settled.
              live: !root.heavy || root.settled
              paintCursor: false
              visible: false
            }
            Rectangle {
              id: roundMask
              anchors.fill: parent
              radius: Math.max(0, frame.rad - frame.bw)
              visible: false
              layer.enabled: true
            }
            MultiEffect {
              anchors.fill: parent
              source: shot
              maskEnabled: true
              maskSource: roundMask
              maskThresholdMin: 0.5
              maskSpreadAtMin: 1.0
            }
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          spacing: 6
          height: 24
          opacity: root.shown && !win.dragging ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 200 } }
          IconImage {
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: 18
            source: root.appIcon(win.modelData)
            visible: source !== ""
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Math.max(80, win.width - 30))
            text: win.ipc.title || win.ipc.class || ""
            color: "white"
            elide: Text.ElideRight
            font.family: root.textFont
            font.pixelSize: 12
            font.weight: win.hot ? Font.DemiBold : Font.Normal
          }
        }

        MouseArea {
          id: winMouse
          anchors.fill: frame
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          drag.target: win
          drag.threshold: 12
          property var hoverThumb: null
          onEntered: root.selected = win.index
          onPressed: win.dragging = false
          onPositionChanged: function(m) {
            if (!drag.active) return
            win.dragging = true
            var p = mapToItem(strip, m.x, m.y)
            var found = null
            for (var i = 0; i < strip.children.length; i++) {
              var c = strip.children[i]
              if (c.dropHover === undefined) continue
              var inside = p.x >= c.x && p.x <= c.x + c.width && p.y >= c.y && p.y <= c.y + c.height
              c.dropHover = inside
              if (inside) found = c
            }
            hoverThumb = found
          }
          onReleased: {
            var target = hoverThumb
            for (var i = 0; i < strip.children.length; i++)
              if (strip.children[i].dropHover !== undefined) strip.children[i].dropHover = false
            hoverThumb = null
            if (win.dragging && target) root.moveWindow(win.modelData, target.modelData)
            win.dragging = false
            // Dragging replaced the bindings; hand the window back to its slot.
            win.x = Qt.binding(function() { return win.targetX })
            win.y = Qt.binding(function() { return win.targetY })
          }
          onClicked: if (!win.dragging) root.focusWindow(win.modelData)
        }
      }
    }

    Text {
      anchors.centerIn: parent
      visible: root.open && root.currentWindows.length === 0
      text: "No windows on this desktop"
      color: Qt.rgba(1, 1, 1, 0.5)
      font.family: root.textFont
      font.pixelSize: 16
      opacity: root.shown ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 200 } }
    }
  }
}
