import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// NASAQ: every window-look setting — transparency, blur, blur colours,
// inactive dim, shadows, shape — as a section list that slides to one page per
// section. Shared by the nasaq.windows bar island and the control center.
//
// Values live in ~/.config/omarchy/nasaq/windows.json. Each change is
// previewed live with `hyprctl eval`; when a slider is released it writes
// ~/.config/hypr/nasaq-windows.lua (loaded last by looknfeel.lua) and reloads
// Hyprland, so the setting survives reboots and config reloads. Both copies
// watch the JSON, so a change in one shows up in the other.
Item {
  id: root

  // "" = the section list; otherwise the open section's key.
  property string page: ""
  // The control center shows a back arrow on the list to return to its main page.
  property bool showBack: false
  signal backRequested()

  implicitHeight: page === "" ? listPage.implicitHeight : detailPage.implicitHeight
  Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

  // ── Settings ───────────────────────────────────────────────────────
  // Values used before anything was saved (what this iMac had on 2026-10-06).
  readonly property var initial: ({
    activeOpacity: 0.65, inactiveOpacity: 0.40,
    blur: true, blurSize: 4, blurPasses: 2,
    vibrancy: 0.2, vibrancyDarkness: 0.25, brightness: 0.8, contrast: 1.0, noise: 0.015,
    dim: false, dimStrength: 0.06,
    rounding: 14, border: 2, gapsIn: 5,
    shadow: false, shadowRange: 4, shadowSpread: 50,
    shadowOpacity: 0.93, shadowAngle: 120, shadowDistance: 0
  })
  // Stock values, restored per slider by double-click: Omarchy's own
  // defaults (default/hypr/looknfeel.lua, windows.lua) where it sets one,
  // otherwise Hyprland's built-in default (the fine blur values, dim strength).
  readonly property var stock: ({
    activeOpacity: 0.985, inactiveOpacity: 0.96,
    blurSize: 8, blurPasses: 1,
    vibrancy: 0.1696, vibrancyDarkness: 0, brightness: 0.8172, contrast: 0.8916, noise: 0.0117,
    dimStrength: 0.5,
    rounding: 0, border: 2, gapsIn: 5,
    shadowRange: 4, shadowSpread: 50,
    shadowOpacity: 0.93, shadowAngle: 120, shadowDistance: 0
  })
  readonly property var defaults: initial
  property var s: Object.assign({}, defaults)
  property bool loaded: false

  // Text or icon drawn on an accent fill: dark on a light accent, white on a dark one.
  readonly property color onAccent: (0.299 * Color.accent.r + 0.587 * Color.accent.g + 0.114 * Color.accent.b) > 0.6 ? "#16181d" : "white"

  // Allowed range per numeric setting (the sliders use the same ranges).
  readonly property var limits: ({
    activeOpacity: [0.2, 1], inactiveOpacity: [0.1, 1],
    blurSize: [1, 15], blurPasses: [1, 4],
    vibrancy: [0, 1], vibrancyDarkness: [0, 1], brightness: [0.3, 1.5], contrast: [0.5, 1.5], noise: [0, 0.1],
    dimStrength: [0, 0.5], rounding: [0, 30], border: [0, 6], gapsIn: [0, 20],
    shadowRange: [1, 60], shadowSpread: [0, 100], shadowOpacity: [0, 1], shadowAngle: [0, 360], shadowDistance: [0, 40]
  })
  // A hand-edited or older file can miss keys or hold text; a NaN written into
  // the Lua file would break the Hyprland config. Fall back to the default and
  // keep every number inside its range.
  function sanitize(values) {
    var out = {}
    for (var k in defaults) {
      var d = defaults[k], v = values ? values[k] : undefined
      if (typeof d === "boolean") { out[k] = v === undefined ? d : !!v; continue }
      var n = Number(v)
      if (v === undefined || v === null || v === "" || !isFinite(n)) n = d
      var lim = limits[k]
      out[k] = lim ? Math.max(lim[0], Math.min(lim[1], n)) : n
    }
    return out
  }

  readonly property string home: Quickshell.env("HOME")

  FileView {
    id: store
    path: root.home + "/.config/omarchy/nasaq/windows.json"
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try { root.s = root.sanitize(JSON.parse(text())) } catch (e) {}
      root.loaded = true
    }
    onLoadFailed: root.loaded = true
  }

  // the user's own default, written by "Save as default", applied by "Restore".
  property var savedDefault: null
  property bool justSaved: false
  FileView {
    id: defaultStore
    path: root.home + "/.config/omarchy/nasaq/windows-default.json"
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { root.savedDefault = JSON.parse(text()) } catch (e) { root.savedDefault = null } }
  }

  // Both buttons overwrite something at once, so each keeps what it replaced
  // for a few seconds behind an Undo button.
  property var undo: null   // { kind: "save" | "restore", previous: <values or null> }
  Timer { id: undoTimer; interval: 8000; onTriggered: root.undo = null }

  function writeDefault(values) {
    savedDefault = values
    defaultStore.setText(values ? JSON.stringify(values, null, 2) + "\n" : "")
    saveTimer.restart()
  }

  function saveDefault() {
    undo = { kind: "save", previous: savedDefault }
    undoTimer.restart()
    writeDefault(Object.assign({}, s))
    justSaved = true
    savedFlash.restart()
  }

  function restoreDefault() {
    if (!savedDefault) return
    undo = { kind: "restore", previous: Object.assign({}, s) }
    undoTimer.restart()
    applyAll(sanitize(savedDefault))
  }

  function undoLast() {
    if (!undo) return
    if (undo.kind === "save") writeDefault(undo.previous)
    else applyAll(undo.previous)
    undo = null
    undoTimer.stop()
  }

  Timer { id: savedFlash; interval: 1600; onTriggered: root.justSaved = false }

  FileView {
    id: luaFile
    path: root.home + "/.config/hypr/nasaq-windows.lua"
    blockLoading: false
    printErrors: false
  }

  function num(v, d) { return Number(v).toFixed(d) }

  function alphaHex(a) {
    var h = Math.round(Math.max(0, Math.min(1, Number(a))) * 255).toString(16)
    return h.length < 2 ? "0" + h : h
  }

  // Photoshop's Spread → Hyprland's falloff: render_power 1–4 (the higher,
  // the faster the falloff), and 100% is `sharp` (a hard edge, "infinite power").
  function spreadPower() {
    return Math.max(1, Math.min(4, 1 + Math.round(Number(s.shadowSpread) / 25)))
  }

  // Photoshop-style angle/distance → Hyprland's x/y offset. The angle is where
  // the light comes from (120° = top-left), so the shadow falls the other way.
  function shadowOffset() {
    var r = Number(s.shadowAngle) * Math.PI / 180
    var d = Number(s.shadowDistance)
    return Math.round(-d * Math.cos(r)) + " " + Math.round(d * Math.sin(r))
  }

  function configLua() {
    var v = s
    return "hl.config({\n"
      + "  general = { border_size = " + Math.round(v.border) + ", gaps_in = " + Math.round(v.gapsIn) + " },\n"
      + "  decoration = {\n"
      + "    rounding = " + Math.round(v.rounding) + ",\n"
      + "    dim_inactive = " + (v.dim ? "true" : "false") + ",\n"
      + "    dim_strength = " + num(v.dimStrength, 3) + ",\n"
      + "    shadow = { enabled = " + (v.shadow ? "true" : "false")
      + ", range = " + Math.round(v.shadowRange) + ", render_power = " + spreadPower()
      + ", sharp = " + (Number(v.shadowSpread) >= 100 ? "true" : "false")
      + ', offset = "' + shadowOffset() + '"'
      + ', color = "rgba(1a1a1a' + alphaHex(v.shadowOpacity) + ')" },\n'
      + "    blur = {\n"
      + "      enabled = " + (v.blur ? "true" : "false") + ",\n"
      + "      size = " + Math.round(v.blurSize) + ",\n"
      + "      passes = " + Math.round(v.blurPasses) + ",\n"
      + "      vibrancy = " + num(v.vibrancy, 3) + ",\n"
      + "      vibrancy_darkness = " + num(v.vibrancyDarkness, 3) + ",\n"
      + "      brightness = " + num(v.brightness, 3) + ",\n"
      + "      contrast = " + num(v.contrast, 3) + ",\n"
      + "      noise = " + num(v.noise, 4) + ",\n"
      + "    },\n"
      + "  },\n"
      + "})\n"
  }

  function opacityLua() {
    var o = '"' + num(s.activeOpacity, 2) + " " + num(s.inactiveOpacity, 2) + ' 1.0"'
    return 'o.window({ tag = "default-opacity" }, { opacity = ' + o + " })\n"
      + 'o.window({ tag = "chromium-based-browser" }, { opacity = ' + o + " })\n"
      + 'o.window({ tag = "firefox-based-browser" }, { opacity = ' + o + " })\n"
  }

  // Live preview while dragging (no file writes, no reload). Throttled: one
  // hyprctl per 40 ms at most, always with the latest values. The opacity
  // sliders have no live preview (they are window rules, applied on release).
  function preview() { previewTimer.start() }
  Timer {
    id: previewTimer
    interval: 40
    onTriggered: Quickshell.execDetached(["hyprctl", "eval", root.configLua()])
  }

  // Persist. Decoration values apply with `hyprctl eval`; only the opacity
  // window rules need a full reload to reach windows that are already open.
  function commit(reload) {
    previewTimer.stop()
    store.setText(JSON.stringify(s, null, 2) + "\n")
    luaFile.setText("-- Generated by the window settings page (nasaq.windows/WindowLook.qml).\n"
      + "-- Change values from Control Center > Windows; this file is rewritten on\n"
      + "-- every change. Loaded last by looknfeel.lua, so it overrides the values there.\n"
      + configLua() + opacityLua())
    if (reload) reloadTimer.restart()
    else Quickshell.execDetached(["hyprctl", "eval", configLua()])
    saveTimer.restart()
  }

  Timer {
    id: reloadTimer
    interval: 250
    onTriggered: Quickshell.execDetached(["hyprctl", "reload"])
  }

  // One the user Settings save per round of adjusting, 20 s after the last
  // change (or when the page goes away), named after the look itself.
  function saveName() {
    return "Window look: " + Math.round(s.activeOpacity * 100) + "/" + Math.round(s.inactiveOpacity * 100)
      + ", blur " + (s.blur ? Math.round(s.blurSize) + "x" + Math.round(s.blurPasses) : "off")
      + ", corners " + Math.round(s.rounding)
  }
  function saveNow() {
    saveTimer.stop()
    Quickshell.execDetached([home + "/.local/bin/nasaq-settings", "save", saveName()])
  }
  Timer { id: saveTimer; interval: 20000; onTriggered: root.saveNow() }
  Component.onDestruction: if (saveTimer.running) saveNow()

  readonly property var reloadKeys: ["activeOpacity", "inactiveOpacity"]

  function set(key, value, final) {
    var next = Object.assign({}, s)
    next[key] = value
    s = next
    if (final) commit(reloadKeys.indexOf(key) !== -1)
    else if (reloadKeys.indexOf(key) === -1) preview()
  }

  // Wheel and typed values: applied live, written once the user stops.
  function nudge(key, value) {
    set(key, value, false)
    if (reloadKeys.indexOf(key) !== -1) nudgeReload = true
    nudgeTimer.restart()
  }
  // Remembered across the whole burst: an opacity nudge followed quickly by
  // another slider must still get its reload.
  property bool nudgeReload: false
  Timer { id: nudgeTimer; interval: 450; onTriggered: { var r = root.nudgeReload; root.nudgeReload = false; root.commit(r) } }

  function applyAll(values) {
    s = sanitize(values)
    commit(true)
  }

  function pct(v) { return Math.round(v * 100) + "%" }
  // Section list: icon, title, one-line summary of the current values.
  readonly property var sections: [
    { key: "transparency", icon: "󰂵", title: "Transparency",
      summary: "Active " + pct(s.activeOpacity) + " · Inactive " + pct(s.inactiveOpacity) },
    { key: "blur", icon: "󰂷", title: "Blur", on: s.blur === true,
      summary: s.blur ? "On · size " + Math.round(s.blurSize) + " · " + Math.round(s.blurPasses) + " passes" : "Off" },
    { key: "colours", icon: "󰏘", title: "Colours",
      summary: "Saturation " + pct(s.vibrancy) + " · Brightness " + pct(s.brightness) },
    { key: "dim", icon: "󰃝", title: "Dim", on: s.dim === true,
      summary: s.dim ? "On · " + pct(s.dimStrength) : "Off" },
    { key: "shadows", icon: "󰘷", title: "Shadows", on: s.shadow === true,
      summary: s.shadow ? "On · " + Math.round(s.shadowAngle) + "° · " + Math.round(s.shadowDistance) + " px · size " + Math.round(s.shadowRange) : "Off" },
    { key: "shape", icon: "󰗆", title: "Shape",
      summary: "Corners " + Math.round(s.rounding) + " · Border " + Math.round(s.border) + " · Gaps " + Math.round(s.gapsIn) }
  ]
  function sectionTitle(k) {
    for (var i = 0; i < sections.length; i++) if (sections[i].key === k) return sections[i].title
    return ""
  }

  // ── Building blocks (same look as the control center) ─────────────
  component Label: Text {
    color: "white"
    font.family: "IBM Plex Sans Arabic"
    font.pixelSize: 13
    font.weight: Font.DemiBold
    elide: Text.ElideRight
  }

  component Sub: Text {
    color: Qt.rgba(1, 1, 1, 0.6)
    font.family: "IBM Plex Sans Arabic"
    font.pixelSize: 11
    elide: Text.ElideRight
  }

  component Switch: Rectangle {
    id: sw
    property bool checked: false
    signal toggled()
    width: 38
    height: 22
    radius: 11
    color: checked ? Color.accent : Qt.rgba(1, 1, 1, 0.22)
    Behavior on color { ColorAnimation { duration: 140 } }
    Rectangle {
      width: 18
      height: 18
      radius: 9
      y: 2
      x: sw.checked ? sw.width - width - 2 : 2
      color: "white"
      Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: sw.toggled()
    }
  }

  // Labelled slider: title and value on top, thin Apple track below.
  component Setting: Column {
    id: st
    property string title: ""
    property string key: ""
    property real from: 0
    property real to: 1
    property real step: 0.01
    property int decimals: 2
    property bool percent: false
    property string suffix: ""
    property bool enabledSetting: true
    readonly property real value: Number(root.s[key])
    width: parent ? parent.width : 0
    spacing: 4
    opacity: enabledSetting ? 1 : 0.4

    function snap(v) {
      var n = Math.round((from + v * (to - from)) / step) * step
      return Math.max(from, Math.min(to, Number(n.toFixed(4))))
    }

    Item {
      width: parent.width
      height: 15
      Sub { anchors.left: parent.left; text: st.title }
      // The value: click it to type an exact number (Enter applies, Esc cancels).
      Sub {
        id: valueText
        anchors.right: parent.right
        color: "white"
        visible: !valueInput.visible
        text: st.percent ? Math.round(st.value * 100) + "%" : st.value.toFixed(st.decimals) + st.suffix
        MouseArea {
          anchors.fill: parent
          anchors.margins: -5
          enabled: st.enabledSetting
          cursorShape: Qt.IBeamCursor
          onClicked: {
            valueInput.text = st.percent ? String(Math.round(st.value * 100)) : st.value.toFixed(st.decimals)
            valueInput.visible = true
            valueInput.forceActiveFocus()
            valueInput.selectAll()
          }
        }
      }
      TextInput {
        id: valueInput
        visible: false
        anchors.right: parent.right
        width: 52
        horizontalAlignment: TextInput.AlignRight
        color: "white"
        selectionColor: Qt.rgba(1, 1, 1, 0.3)
        font.family: "IBM Plex Sans Arabic"
        font.pixelSize: 11
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        function apply() {
          if (!visible) return
          visible = false
          var n = parseFloat(text.replace(",", "."))
          if (!isFinite(n)) return
          if (st.percent) n = n / 100
          var v = Math.max(st.from, Math.min(st.to, Number((Math.round(n / st.step) * st.step).toFixed(4))))
          if (v !== st.value) root.set(st.key, v, true)
        }
        onAccepted: apply()
        Keys.onEscapePressed: visible = false
        // Clicking elsewhere keeps what was typed, like any settings field.
        onActiveFocusChanged: if (!activeFocus) apply()
        Rectangle {
          anchors.fill: parent
          anchors.margins: -3
          z: -1
          radius: 4
          color: Qt.rgba(1, 1, 1, 0.14)
        }
      }
    }

    Item {
      width: parent.width
      height: 16
      Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: Qt.rgba(1, 1, 1, 0.16)
        Rectangle {
          height: parent.height
          radius: 3
          width: parent.width * Math.max(0, Math.min(1, (st.value - st.from) / (st.to - st.from)))
          color: Qt.rgba(1, 1, 1, 0.92)
        }
      }
      Rectangle {
        width: 18
        height: 18
        radius: 9
        anchors.verticalCenter: parent.verticalCenter
        x: (parent.width - width) * Math.max(0, Math.min(1, (st.value - st.from) / (st.to - st.from)))
        color: "white"
        border.color: Qt.rgba(0, 0, 0, 0.25)
      }
      MouseArea {
        anchors.fill: parent
        anchors.margins: -8
        // Wheel: one step per notch.
        property real wheelAcc: 0
        onWheel: function(w) {
          if (!st.enabledSetting) return
          // One step per mouse notch (120 units); a touchpad's stream of small
          // deltas adds up to the same instead of one step per event.
          wheelAcc += w.angleDelta.y
          var steps = wheelAcc > 0 ? Math.floor(wheelAcc / 120) : Math.ceil(wheelAcc / 120)
          if (steps === 0) return
          wheelAcc -= steps * 120
          var v = Math.max(st.from, Math.min(st.to, Number((st.value + steps * st.step).toFixed(4))))
          if (v !== st.value) root.nudge(st.key, v)
        }
        enabled: st.enabledSetting
        cursorShape: Qt.PointingHandCursor
        function at(x) { return st.snap(Math.max(0, Math.min(1, x / width))) }
        onPressed: function(e) { root.set(st.key, at(e.x), false) }
        onPositionChanged: function(e) { if (pressed) root.set(st.key, at(e.x), false) }
        onReleased: function(e) { root.set(st.key, at(e.x), true) }
        onDoubleClicked: if (root.stock[st.key] !== undefined) root.set(st.key, root.stock[st.key], true)
      }
    }
  }


  // ── Section list ──
  Column {
    id: listPage
    x: root.page === "" ? 0 : -parent.width
    width: parent.width
    spacing: 6
    opacity: root.page === "" ? 1 : 0
    visible: opacity > 0
    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 160 } }

    Item {
      width: parent.width
      height: 30
      Rectangle {
        id: listBack
        visible: root.showBack
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? 26 : 0
        height: 26
        radius: 13
        color: listBackMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
        Text {
          anchors.centerIn: parent
          text: "󰅁"
          color: "white"
          font.family: Style.font.family
          font.pixelSize: 14
        }
        MouseArea {
          id: listBackMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.backRequested()
        }
      }
      Label {
        anchors.left: listBack.right
        anchors.leftMargin: root.showBack ? 6 : 4
        anchors.verticalCenter: parent.verticalCenter
        text: "Windows"
        font.pixelSize: 15
        font.weight: Font.Bold
      }
    }

    Rectangle {
      width: parent.width
      height: sectionCol.implicitHeight + 8
      radius: 14
      color: Qt.rgba(1, 1, 1, 0.08)
      border.color: Qt.rgba(1, 1, 1, 0.06)
      border.width: 1

      Column {
        id: sectionCol
        x: 4
        y: 4
        width: parent.width - 8

        Repeater {
          model: root.sections
          delegate: Rectangle {
            required property var modelData
            required property int index
            width: sectionCol.width
            height: 50
            radius: 10
            color: rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"

            Rectangle {
              id: rowIcon
              anchors.left: parent.left
              anchors.leftMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              width: 30
              height: 30
              radius: 15
              // Accent only where something is switched on; plain for the rest.
              color: modelData.on === true ? Color.accent : Qt.rgba(1, 1, 1, 0.14)
              Behavior on color { ColorAnimation { duration: 140 } }
              Text {
                anchors.centerIn: parent
                text: modelData.icon
                color: modelData.on === true ? root.onAccent : "white"
                font.family: Style.font.family
                font.pixelSize: 15
              }
            }
            Column {
              anchors.left: rowIcon.right
              anchors.leftMargin: 10
              anchors.right: chevron.left
              anchors.rightMargin: 6
              anchors.verticalCenter: parent.verticalCenter
              spacing: 1
              Label { width: parent.width; text: modelData.title }
              Sub { width: parent.width; text: modelData.summary }
            }
            Text {
              id: chevron
              anchors.right: parent.right
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              text: "󰅂"
              color: "white"
              font.family: Style.font.family
              font.pixelSize: 12
              opacity: rowMouse.containsMouse ? 0.8 : 0.35
            }
            Rectangle {
              visible: index < root.sections.length - 1
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              anchors.leftMargin: 48
              anchors.right: parent.right
              height: 1
              color: Qt.rgba(1, 1, 1, 0.07)
            }
            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.page = modelData.key
            }
          }
        }
      }
    }
    // My default: save what is on screen now, or go back to it.
    Row {
      width: parent.width
      spacing: 8
      topPadding: 2

      Rectangle {
        width: (parent.width - 8) / 2
        height: 34
        radius: 17
        opacity: root.savedDefault ? 1 : 0.4
        color: Qt.rgba(1, 1, 1, restoreMouse.containsMouse && root.savedDefault ? 0.18 : 0.10)
        Sub { anchors.centerIn: parent; color: "white"; font.weight: Font.DemiBold; text: "Restore my default" }
        MouseArea {
          id: restoreMouse
          anchors.fill: parent
          enabled: !!root.savedDefault
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.restoreDefault()
        }
      }

      Rectangle {
        width: (parent.width - 8) / 2
        height: 34
        radius: 17
        color: root.justSaved ? "#30d158" : (saveMouse.containsMouse ? Qt.lighter(Color.accent, 1.12) : Color.accent)
        Behavior on color { ColorAnimation { duration: 160 } }
        Sub { anchors.centerIn: parent; color: root.justSaved ? "white" : root.onAccent; font.weight: Font.DemiBold; text: root.justSaved ? "Saved ✓" : "Save as default" }
        MouseArea {
          id: saveMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.saveDefault()
        }
      }
    }

    // Undo for the two buttons above, shown for a few seconds after either.
    Rectangle {
      width: parent.width
      height: 30
      radius: 15
      visible: root.undo !== null
      color: Qt.rgba(1, 1, 1, undoMouse.containsMouse ? 0.18 : 0.10)
      Sub {
        anchors.centerIn: parent
        color: "white"
        font.weight: Font.DemiBold
        text: root.undo && root.undo.kind === "save" ? "Undo: keep my previous default" : "Undo: go back to the look I had"
      }
      MouseArea {
        id: undoMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.undoLast()
      }
    }
  }

  // ── Section page ──
  Column {
    id: detailPage
    x: root.page !== "" ? 0 : parent.width
    width: parent.width
    spacing: 8
    opacity: root.page !== "" ? 1 : 0
    visible: opacity > 0
    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 160 } }

    // Back · title · on/off switch for sections that have one.
    Item {
      width: parent.width
      height: 30
      Rectangle {
        id: back
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 26
        height: 26
        radius: 13
        color: backMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
        Text {
          anchors.centerIn: parent
          text: "󰅁"
          color: "white"
          font.family: Style.font.family
          font.pixelSize: 14
        }
        MouseArea {
          id: backMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.page = ""
        }
      }
      Label {
        anchors.left: back.right
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        text: root.sectionTitle(root.page)
        font.pixelSize: 15
        font.weight: Font.Bold
      }
      Switch {
        readonly property string toggleKey: root.page === "blur" ? "blur" : root.page === "dim" ? "dim" : root.page === "shadows" ? "shadow" : ""
        visible: toggleKey !== ""
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        checked: toggleKey !== "" && !!root.s[toggleKey]
        onToggled: root.set(toggleKey, !root.s[toggleKey], true)
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Qt.rgba(1, 1, 1, 0.12)
    }

    Rectangle {
      width: parent.width
      height: settingsCol.implicitHeight + 22
      radius: 14
      color: Qt.rgba(1, 1, 1, 0.08)
      border.color: Qt.rgba(1, 1, 1, 0.06)
      border.width: 1

      Column {
        id: settingsCol
        x: 11
        y: 11
        width: parent.width - 22
        spacing: 10

        // Transparency
        Setting { visible: root.page === "transparency"; title: "Active window"; key: "activeOpacity"; from: 0.2; to: 1; step: 0.01; percent: true }
        Setting { visible: root.page === "transparency"; title: "Inactive windows"; key: "inactiveOpacity"; from: 0.1; to: 1; step: 0.01; percent: true }
        // Blur
        Setting { visible: root.page === "blur"; title: "Size"; key: "blurSize"; from: 1; to: 15; step: 1; decimals: 0; enabledSetting: root.s.blur }
        Setting { visible: root.page === "blur"; title: "Passes"; key: "blurPasses"; from: 1; to: 4; step: 1; decimals: 0; enabledSetting: root.s.blur }
        // Colours (they tint what shows through the blur)
        Setting { visible: root.page === "colours"; title: "Saturation (vibrancy)"; key: "vibrancy"; from: 0; to: 1; step: 0.01; enabledSetting: root.s.blur }
        Setting { visible: root.page === "colours"; title: "Saturation in dark areas"; key: "vibrancyDarkness"; from: 0; to: 1; step: 0.01; enabledSetting: root.s.blur }
        Setting { visible: root.page === "colours"; title: "Brightness"; key: "brightness"; from: 0.3; to: 1.5; step: 0.01; enabledSetting: root.s.blur }
        Setting { visible: root.page === "colours"; title: "Contrast"; key: "contrast"; from: 0.5; to: 1.5; step: 0.01; enabledSetting: root.s.blur }
        Setting { visible: root.page === "colours"; title: "Grain (noise)"; key: "noise"; from: 0; to: 0.1; step: 0.001; decimals: 3; enabledSetting: root.s.blur }
        Sub { visible: root.page === "colours" && !root.s.blur; width: parent.width; wrapMode: Text.WordWrap; text: "Colours apply to the blur — turn Blur on to use them." }
        // Dim
        Setting { visible: root.page === "dim"; title: "Strength"; key: "dimStrength"; from: 0; to: 0.5; step: 0.01; enabledSetting: root.s.dim }
        // Shadows
        Setting { visible: root.page === "shadows"; title: "Opacity"; key: "shadowOpacity"; from: 0; to: 1; step: 0.01; percent: true; enabledSetting: root.s.shadow }
        Setting { visible: root.page === "shadows"; title: "Angle"; key: "shadowAngle"; from: 0; to: 360; step: 1; decimals: 0; suffix: "°"; enabledSetting: root.s.shadow }
        Setting { visible: root.page === "shadows"; title: "Distance"; key: "shadowDistance"; from: 0; to: 40; step: 1; decimals: 0; suffix: " px"; enabledSetting: root.s.shadow }
        Setting { visible: root.page === "shadows"; title: "Spread"; key: "shadowSpread"; from: 0; to: 100; step: 25; decimals: 0; suffix: "%"; enabledSetting: root.s.shadow }
        Setting { visible: root.page === "shadows"; title: "Size"; key: "shadowRange"; from: 1; to: 60; step: 1; decimals: 0; suffix: " px"; enabledSetting: root.s.shadow }
        // Shape
        Setting { visible: root.page === "shape"; title: "Corner rounding"; key: "rounding"; from: 0; to: 30; step: 1; decimals: 0 }
        Setting { visible: root.page === "shape"; title: "Border width"; key: "border"; from: 0; to: 6; step: 1; decimals: 0 }
        Setting { visible: root.page === "shape"; title: "Gap between windows"; key: "gapsIn"; from: 0; to: 20; step: 1; decimals: 0 }
      }
    }

    Sub {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: "Double-click a slider to reset it. Click a number to type."
    }
  }
}
