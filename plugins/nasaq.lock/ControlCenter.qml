import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.Commons
// A copy of nasaq.audio/Model.js lives here on purpose: the lock screen loads
// this file, so it must not depend on another plugin's folder being present.
import "AudioModel.js" as AudioModel

// NASAQ: quick settings, shared by the lock screen (LockView) and
// the bar (nasaq.control-center). The main page has the Wi-Fi/Bluetooth tile,
// keyboard, battery, brightness, sound and power; clicking Wi-Fi or Bluetooth
// slides to a detail page with the network / device list.
Item {
  id: root

  property string textFont: ""
  property string iconFont: ""
  property bool active: false
  property bool interactive: true
  property bool opened: false
  // The bar copy adds a Lock button, links to the full settings panels, and
  // sits on bare windows (no blur), so it needs a more opaque card.
  property bool showLock: false
  property real panelAlpha: 0.80
  // The bar draws its own morphing island frame around this, so the card
  // drops its background and pop animation and just fades its content.
  property bool chromeless: false
  // The bar's always-visible pill shows the keyboard layout, so it polls
  // faster than the lock screen needs to while the panel is closed.
  // (the layout itself arrives by Hyprland event; this poll is for brightness
  // and the power profile, which only matter while the panel is open).
  property int pollInterval: opened ? 2000 : 30000

  signal interacted()
  signal closeRequested()

  // "" (main), "wifi", "bluetooth", "sound" or "windows"
  property string page: ""
  // Wi-Fi network whose inline password prompt is open, the one being joined,
  // and the last one that failed.
  property string promptSsid: ""
  property string pendingSsid: ""
  property string failedSsid: ""
  property string pendingAddress: ""
  property bool ownsDiscovery: false
  // True while a field inside the panel needs the keyboard, so the lock
  // screen stops pulling focus back to its own password field.
  readonly property bool keyboardBusy: promptSsid !== ""

  // ── Live state ─────────────────────────────────────────────────────
  // Connection details from `omarchy-network-status --verbose`, sampled while
  // the Wi-Fi page is open; rates are byte-counter deltas between samples.
  property var netInfo: ({})
  property real downRate: -1
  property real upRate: -1
  property string statIface: ""
  property real prevRx: 0
  property real prevTx: 0
  property real prevSampleAt: 0
  property string dnsProvider: ""
  property string pendingDns: ""
  readonly property bool netConnected: !!netInfo.iface
  property string layoutFull: ""
  property int brightness: -1
  // Power profile (power-profiles-daemon). Omarchy remembers one per power
  // source and switches on plug/unplug; picking one here saves it for the
  // current source.
  property string powerProfile: ""
  property var powerProfiles: []
  property string pendingProfile: ""

  readonly property var wifiDevice: {
    var devices = Networking.devices ? Networking.devices.values : []
    var fallback = null
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (!d || d.type !== DeviceType.Wifi) continue
      if (d.connected) return d
      if (!fallback) fallback = d
    }
    return fallback
  }
  readonly property var networks: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
  readonly property bool wifiOn: Networking.wifiEnabled
  readonly property var currentNetwork: {
    for (var i = 0; i < networks.length; i++) if (networks[i] && networks[i].connected) return networks[i]
    return null
  }
  readonly property string ssid: currentNetwork ? (currentNetwork.name || "") : ""
  readonly property int wifiSignal: currentNetwork ? Math.round((currentNetwork.signalStrength || 0) * 100) : 0
  readonly property var knownNetworks: sortedNetworks(function(n) { return !n.connected && n.known })
  readonly property var otherNetworks: sortedNetworks(function(n) { return !n.connected && !n.known })

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property bool bluetoothOn: !!adapter && adapter.enabled
  readonly property var btDevices: Bluetooth.devices ? Bluetooth.devices.values : []
  readonly property var pairedDevices: btDevices.filter(function(d) { return d && (d.paired || d.bonded || d.trusted) })
    .sort(function(a, b) { return (b.connected ? 1 : 0) - (a.connected ? 1 : 0) || deviceName(a).localeCompare(deviceName(b)) })
  readonly property var nearbyDevices: btDevices.filter(function(d) {
    return d && !(d.paired || d.bonded || d.trusted) && deviceName(d) !== "" && deviceName(d) !== d.address
  })
  readonly property int connectedBtCount: btDevices.filter(function(d) { return d && d.connected }).length

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
  readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
  readonly property var source: Pipewire.defaultAudioSource
  readonly property real inputVolume: source && source.audio ? source.audio.volume : 0
  readonly property bool inputMuted: source && source.audio ? source.audio.muted : false

  // Sound page lists. Like nasaq.audio, the Repeaters read snapshots that are
  // refreshed on a short timer rather than the live PipeWire model (rebuilding
  // a Repeater inside PipeWire's node-removal signal has crashed Quickshell),
  // and they are emptied whenever the page is not showing.
  readonly property bool soundWanted: opened && page === "sound"
  readonly property var pwNodes: soundWanted && Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var liveSinks: pwNodes.filter(function(n) {
    return n && n.isSink && !n.isStream && sinkAvailability[String(n.name)] !== false
  })
  readonly property var liveSources: pwNodes.filter(function(n) {
    return n && !n.isSink && !n.isStream && AudioModel.isAudioSource(n) && String(n.name || "") !== "quickshell"
  })
  readonly property var liveStreams: pwNodes.filter(function(n) {
    return n && AudioModel.isPlaybackStream(n) && n.audio
      && String(n.name || "").indexOf("omarchy_speaker_tuning") !== 0
  })
  property var sinkAvailability: ({})
  property var shownSinks: []
  property var shownSources: []
  property var shownStreams: []

  readonly property var battery: UPower.displayDevice
  readonly property int batteryPercent: battery && battery.isPresent ? Math.round(Number(battery.percentage || 0) * 100) : -1
  readonly property bool charging: !!battery && battery.isPresent && !UPower.onBattery

  readonly property string layoutShort: {
    var l = layoutFull
    if (!l) return ""
    if (l.indexOf("Arabic") !== -1) return "AR"
    var m = l.match(/\(([A-Z]{2})\)/)
    return m ? m[1] : l.slice(0, 2).toUpperCase()
  }
  readonly property string wifiIcon: !wifiOn ? "󰖪" : (ssid.length === 0 ? "󰤯" : signalIcon(wifiSignal))
  readonly property string batteryIcon: {
    if (charging) return "󰂄"
    var icons = ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
    return icons[Math.max(0, Math.min(10, Math.round(batteryPercent / 10)))]
  }

  // Colours follow the active Omarchy theme with the same mapping as the lock
  // and login screens: Color.foreground for text, icons and the glass tint,
  // Color.accent for accents, Color.background as the dark base, Color.urgent
  // for armed or failing states. Inline components use Color.* directly.
  // The theme's accent (it used to be a fixed blue), so a theme change carries over.
  readonly property color accent: Color.accent
  // Text or icon drawn on an accent fill: dark on a light accent, white on a dark one.
  readonly property color onAccent: (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.6 ? "#16181d" : "white"

  width: 320
  height: panel.height
  visible: panel.opacity > 0
  enabled: opened && interactive

  function run(cmd) {
    Quickshell.execDetached(["bash", "-c", cmd])
    root.interacted()
    refreshSoon.restart()
  }

  function signalIcon(pct) {
    return pct >= 75 ? "󰤨" : pct >= 50 ? "󰤥" : pct >= 25 ? "󰤢" : "󰤟"
  }

  function sortedNetworks(pred) {
    var seen = ({})
    var out = []
    for (var i = 0; i < networks.length; i++) {
      var n = networks[i]
      if (!n || !n.name || seen[n.name] || !pred(n)) continue
      seen[n.name] = true
      out.push(n)
    }
    return out.sort(function(a, b) { return (b.signalStrength || 0) - (a.signalStrength || 0) })
  }

  function isSecured(n) {
    return !!n && n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe
  }

  function deviceName(d) {
    return d ? String(d.name || d.deviceName || "").trim() : ""
  }

  function deviceIcon(d) {
    var i = String(d && d.icon || "")
    if (/head|audio-card|earbud/.test(i)) return "󰋋"
    if (/speaker/.test(i)) return "󰓃"
    if (/mouse/.test(i)) return "󰍽"
    if (/keyboard/.test(i)) return "󰌌"
    if (/phone/.test(i)) return "󰏲"
    if (/computer|laptop/.test(i)) return "󰟀"
    if (/watch/.test(i)) return "󰖉"
    if (/gaming|joystick/.test(i)) return "󰊴"
    return "󰂯"
  }

  function formatRate(bytesPerSec) {
    if (bytesPerSec < 0) return "—"
    var units = ["B/s", "KB/s", "MB/s", "GB/s"]
    var v = bytesPerSec, i = 0
    while (v >= 1000 && i < units.length - 1) { v /= 1000; i++ }
    return (v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)) + " " + units[i]
  }

  function updateStats(raw) {
    var next = ({})
    String(raw || "").split("\n").forEach(function(line) {
      var t = line.indexOf("\t")
      if (t > 0) next[line.slice(0, t)] = line.slice(t + 1)
    })
    var now = Date.now() / 1000
    var rx = parseFloat(next.rx_bytes || "0"), tx = parseFloat(next.tx_bytes || "0")
    if (next.iface && next.iface === statIface && prevSampleAt > 0 && now > prevSampleAt) {
      downRate = Math.max(0, (rx - prevRx) / (now - prevSampleAt))
      upRate = Math.max(0, (tx - prevTx) / (now - prevSampleAt))
    } else {
      downRate = -1
      upRate = -1
    }
    statIface = next.iface || ""
    prevRx = rx
    prevTx = tx
    prevSampleAt = now
    netInfo = next
  }

  function setDns(provider) {
    if (!provider || dnsProc.running) return
    if (provider === "Custom") {
      closeRequested()
      Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", "omarchy-dns Custom"])
      return
    }
    pendingDns = provider
    dnsProc.command = ["omarchy-dns", provider]
    dnsProc.running = true
    interacted()
  }

  function runSpeedTest() {
    closeRequested()
    var payload = netInfo.type === "wifi" ? JSON.stringify({ connection: netInfo.ssid || "Wi-Fi" }) : "{}"
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", "omarchy.speedtest", payload])
  }

  function refreshSoundLists() {
    if (!soundWanted) return
    shownSinks = liveSinks.slice()
    shownSources = liveSources.slice()
    shownStreams = liveStreams.slice()
  }

  function setDefaultSink(n) {
    if (!n) return
    Pipewire.preferredDefaultAudioSink = n
    if (n.id !== undefined && n.name) Quickshell.execDetached(["omarchy-audio-output-set-default", String(n.id), String(n.name)])
    interacted()
  }

  function setDefaultSource(n) {
    if (!n) return
    Pipewire.preferredDefaultAudioSource = n
    if (n.id !== undefined && n.name) Quickshell.execDetached(["omarchy-audio-input-set-default", String(n.id), String(n.name)])
    interacted()
  }

  // "CS4206 Analog" means nothing to a person: the machine's own analog
  // output and input are just its speakers and microphone.
  function deviceLabel(n, isSink) {
    if (/^alsa_(output|input)\.pci-.*analog/.test(String(n && n.name || "")))
      return isSink ? "Built-in Speakers" : "Built-in Microphone"
    return AudioModel.nodeLabel(n)
  }

  function volumeIcon(v, m) {
    return m ? "󰝟" : (v < 0.34 ? "󰕿" : v < 0.67 ? "󰖀" : "󰕾")
  }

  onSoundWantedChanged: {
    if (soundWanted) {
      refreshSoundLists()
      if (!sinkAvailProc.running) sinkAvailProc.running = true
    } else {
      soundListTimer.stop()
      shownSinks = []
      shownSources = []
      shownStreams = []
    }
  }
  onLiveSinksChanged: if (soundWanted) soundListTimer.restart()
  onLiveSourcesChanged: if (soundWanted) soundListTimer.restart()
  onLiveStreamsChanged: if (soundWanted) soundListTimer.restart()

  // Straight to one section of the Windows page (used by the bar's IPC).
  function openWindowsSection(name) {
    openPage("windows")
    Qt.callLater(function() { if (winLoader.item) winLoader.item.page = name })
  }

  function openPage(name) {
    promptSsid = ""
    failedSsid = ""
    page = name
    interacted()
  }

  function joinNetwork(n) {
    if (!n) return
    failedSsid = ""
    if (n.connected) {
      n.disconnect()
      interacted()
      return
    }
    if (isSecured(n) && !n.known) {
      promptSsid = n.name
      return
    }
    promptSsid = ""
    pendingSsid = n.name
    n.connect()
    pendingClear.restart()
    interacted()
  }

  function submitPassword(n, password) {
    if (!n || password.length === 0) return
    promptSsid = ""
    pendingSsid = n.name
    n.connectWithPsk(password)
    pendingClear.restart()
    interacted()
  }

  function toggleDevice(d) {
    if (!d || !d.address) return
    pendingAddress = d.address
    pendingClear.restart()
    var action = d.connected ? "disconnect" : ((d.paired || d.bonded || d.trusted) ? "connect" : "pair")
    Quickshell.execDetached(["omarchy-bluetooth-device", action, d.address])
    interacted()
  }

  onOpenedChanged: if (!opened) resetPage.restart()
  onPageChanged: { syncDiscovery(); if (page !== "windows") winKeep.restart() }
  onBluetoothOnChanged: syncDiscovery()

  // Scan for nearby devices only while the Bluetooth page is showing, and only
  // stop a scan this panel started.
  function syncDiscovery() {
    if (!adapter) return
    var want = opened && page === "bluetooth" && bluetoothOn
    if (want && !adapter.discovering) {
      adapter.discovering = true
      ownsDiscovery = true
    } else if (!want && ownsDiscovery) {
      if (adapter.discovering) adapter.discovering = false
      ownsDiscovery = false
    }
  }

  // Keep the scanner fresh while the Wi-Fi list is open.
  Binding {
    target: root.wifiDevice
    property: "scannerEnabled"
    value: true
    when: root.wifiDevice !== null && root.opened && root.page === "wifi" && root.wifiOn
    restoreMode: Binding.RestoreValue
  }

  Timer {
    id: resetPage
    interval: 200
    onTriggered: {
      root.page = ""
      root.promptSsid = ""
      root.failedSsid = ""
      root.syncDiscovery()
    }
  }

  Timer {
    id: pendingClear
    interval: 20000
    onTriggered: { root.pendingSsid = ""; root.pendingAddress = "" }
  }

  PwObjectTracker { objects: root.sink ? [root.sink] : [] }
  PwObjectTracker { objects: root.soundWanted ? root.liveSinks.concat(root.liveSources, root.liveStreams, root.source ? [root.source] : []) : [] }

  // Auto brightness: ~/.local/bin/nasaq-auto-brightness follows the ambient
  // light sensor while it is on. `status` prints "sensor" when the machine has
  // one and "on" when the service is enabled.
  property bool hasLightSensor: false
  property bool autoBright: false
  Process {
    id: autoBrightProc
    command: [Quickshell.env("HOME") + "/.local/bin/nasaq-auto-brightness", "status"]
    running: root.showLock
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var words = String(text || "").trim().split(/\s+/)
        root.hasLightSensor = words.indexOf("sensor") !== -1
        root.autoBright = words.indexOf("on") !== -1
      }
    }
  }
  function setAutoBright(on) {
    autoBright = on
    Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/nasaq-auto-brightness", on ? "on" : "off"])
    interacted()
  }

  // Do Not Disturb, as published by nasaq.notifications in its island state file.
  property bool dnd: false
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/nasaq/island-toast.json"
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { root.dnd = JSON.parse(text()).dnd === true } catch (e) {} }
  }

  // Fix Sound only exists on the iMac (~/.local/bin/fix-sound rebinds its
  // CS4206 card); elsewhere the button is hidden.
  property bool hasFixSound: false
  Process {
    command: ["test", "-x", Quickshell.env("HOME") + "/.local/bin/fix-sound"]
    running: true
    onExited: function(code) { root.hasFixSound = code === 0 }
  }

  Timer { id: soundListTimer; interval: 75; onTriggered: root.refreshSoundLists() }

  Process {
    id: sinkAvailProc
    command: ["omarchy-audio-sink-availability"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.sinkAvailability = AudioModel.parseSinkAvailability(text)
    }
  }

  readonly property bool statsWanted: opened && page === "wifi"
  onStatsWantedChanged: {
    if (!statsWanted) return
    statIface = ""
    prevSampleAt = 0
    downRate = -1
    upRate = -1
    if (!dnsReadProc.running) dnsReadProc.running = true
  }

  Process {
    id: statsProc
    command: ["omarchy-network-status", "--verbose"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateStats(text) }
  }

  Timer {
    interval: 1500
    repeat: true
    triggeredOnStart: true
    running: root.statsWanted
    onTriggered: if (!statsProc.running) statsProc.running = true
  }

  Process {
    id: dnsReadProc
    command: ["omarchy-dns"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.dnsProvider = String(text || "").trim() || "DHCP" }
  }

  Process {
    id: dnsProc
    onExited: function(exitCode) {
      if (exitCode === 0 && root.pendingDns) root.dnsProvider = root.pendingDns
      root.pendingDns = ""
    }
  }

  // Hyprland announces every layout switch ("keyboard,Layout name"), so the
  // layout label follows a key press immediately instead of waiting a poll.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || event.name !== "activelayout") return
      var data = String(event.data || "")
      var comma = data.indexOf(",")
      if (comma >= 0) root.layoutFull = data.slice(comma + 1)
    }
  }

  Process {
    id: poll
    command: ["bash", "-c",
      "echo \"kb=$(hyprctl devices -j 2>/dev/null | jq -r '([.keyboards[] | select(.main)] | .[0].active_keymap) // .keyboards[0].active_keymap // \"\"')\"; " +
      "echo \"bright=$(brightnessctl -m -c backlight 2>/dev/null | head -1 | cut -d, -f4 | tr -d %)\"; " +
      // Over D-Bus, not powerprofilesctl/omarchy-powerprofiles-list: those run
      // Python, which intermittently segfaults on exit (crash analysis 2026-10-07).
      "pp='net.hadess.PowerProfiles /net/hadess/PowerProfiles net.hadess.PowerProfiles'; " +
      "echo \"prof=$(busctl get-property $pp ActiveProfile 2>/dev/null | sed -E 's/^s \\\"(.*)\\\"$/\\1/')\"; " +
      "echo \"profs=$(busctl -j get-property $pp Profiles 2>/dev/null | jq -r '.data[].Profile.data' 2>/dev/null | tr '\\n' ' ')\""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = { kb: "", bright: "", prof: "", profs: "" }
        String(text || "").split("\n").forEach(function(line) {
          var i = line.indexOf("=")
          if (i > 0) next[line.slice(0, i)] = line.slice(i + 1)
        })
        root.layoutFull = next.kb
        if (!root.pendingProfile) root.powerProfile = next.prof
        root.powerProfiles = next.profs.trim().length > 0 ? next.profs.trim().split(/\s+/) : []
        if (!brightnessSlider.dragging) root.brightness = next.bright === "" ? -1 : (parseInt(next.bright) || 0)
      }
    }
  }

  Timer {
    interval: root.pollInterval
    running: root.active
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!poll.running) poll.running = true
  }

  Timer {
    id: profileClear
    interval: 1500
    onTriggered: root.pendingProfile = ""
  }

  Timer {
    id: refreshSoon
    interval: 700
    onTriggered: if (!poll.running) poll.running = true
  }

  Timer {
    id: brightnessWriter
    interval: 60
    property int pending: -1
    onTriggered: if (pending >= 0) Quickshell.execDetached(["brightnessctl", "-q", "-c", "backlight", "set", pending + "%"])
  }

  // ── Building blocks ────────────────────────────────────────────────
  component Tile: Rectangle {
    radius: 14
    color: Util.alpha(Color.foreground, 0.08)
    border.color: Util.alpha(Color.foreground, 0.06)
    border.width: 1
  }

  component Label: Text {
    color: Color.foreground
    font.family: root.textFont
    font.pixelSize: 13
    font.weight: Font.DemiBold
    elide: Text.ElideRight
  }

  component Sub: Text {
    color: Util.alpha(Color.foreground, 0.6)
    font.family: root.textFont
    font.pixelSize: 11
    elide: Text.ElideRight
  }

  component Glyph: Text {
    color: Color.foreground
    font.family: root.iconFont
    font.pixelSize: 15
  }

  component Divider: Rectangle {
    height: 1
    color: Util.alpha(Color.foreground, 0.12)
  }

  component SectionTitle: Text {
    color: Util.alpha(Color.foreground, 0.5)
    font.family: root.textFont
    font.pixelSize: 11
    font.weight: Font.DemiBold
    leftPadding: 4
    topPadding: 4
  }

  component RoundIcon: Rectangle {
    property string icon: ""
    property bool on: false
    property int size: 30
    property bool clickable: true
    signal clicked()
    width: size
    height: size
    radius: size / 2
    color: on ? root.accent : Util.alpha(Color.foreground, iconMouse.containsMouse ? 0.24 : 0.15)
    Behavior on color { ColorAnimation { duration: 120 } }
    Glyph {
      anchors.centerIn: parent
      text: parent.icon
      color: parent.on ? root.onAccent : Color.foreground
      font.pixelSize: Math.round(parent.size * 0.5)
    }
    MouseArea {
      id: iconMouse
      anchors.fill: parent
      enabled: parent.clickable
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: parent.clicked()
    }
  }

  // Pill switch.
  component Switch: Rectangle {
    id: sw
    property bool checked: false
    signal toggled()
    width: 38
    height: 22
    radius: 11
    color: checked ? root.accent : Util.alpha(Color.foreground, 0.22)
    Behavior on color { ColorAnimation { duration: 140 } }
    Rectangle {
      width: 18
      height: 18
      radius: 9
      y: 2
      x: sw.checked ? sw.width - width - 2 : 2
      color: Color.foreground
      Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: sw.toggled()
    }
  }

  // Main-page row: the round icon toggles, the rest of the row opens the page.
  component ToggleRow: Rectangle {
    id: tr
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool on: false
    signal toggled()
    signal expand()
    height: 40
    radius: 10
    color: rowMouse.containsMouse ? Util.alpha(Color.foreground, 0.07) : "transparent"
    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tr.expand()
    }
    RoundIcon {
      id: rowIcon
      anchors.left: parent.left
      anchors.leftMargin: 2
      anchors.verticalCenter: parent.verticalCenter
      icon: tr.icon
      on: tr.on
      onClicked: tr.toggled()
    }
    Column {
      anchors.left: rowIcon.right
      anchors.leftMargin: 9
      anchors.right: chevron.left
      anchors.verticalCenter: parent.verticalCenter
      Label { width: parent.width; text: tr.title }
      Sub { width: parent.width; text: tr.subtitle }
    }
    Glyph {
      id: chevron
      anchors.right: parent.right
      anchors.rightMargin: 4
      anchors.verticalCenter: parent.verticalCenter
      text: "󰅂"
      font.pixelSize: 12
      opacity: rowMouse.containsMouse ? 0.8 : 0.35
    }
  }

  // Row in a detail-page list.
  component ListRow: Rectangle {
    id: lr
    property string icon: ""
    property string title: ""
    property string trailing: ""
    property string trailingIcon: ""
    property bool on: false
    property bool busy: false
    signal clicked()
    width: parent ? parent.width : 0
    height: 36
    radius: 8
    color: lrMouse.containsMouse ? Util.alpha(Color.foreground, 0.08) : "transparent"
    MouseArea {
      id: lrMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: lr.clicked()
    }
    RoundIcon {
      id: lrIcon
      anchors.left: parent.left
      anchors.leftMargin: 4
      anchors.verticalCenter: parent.verticalCenter
      size: 26
      clickable: false
      icon: lr.icon
      on: lr.on
    }
    Label {
      anchors.left: lrIcon.right
      anchors.leftMargin: 9
      anchors.right: trailingRow.left
      anchors.rightMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      text: lr.title
      font.weight: Font.Normal
    }
    Row {
      id: trailingRow
      anchors.right: parent.right
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      spacing: 6
      Sub {
        anchors.verticalCenter: parent.verticalCenter
        text: lr.busy ? "Connecting…" : lr.trailing
        visible: text.length > 0
      }
      Glyph {
        anchors.verticalCenter: parent.verticalCenter
        text: lr.trailingIcon
        visible: text.length > 0 && !lr.busy
        font.pixelSize: 12
        opacity: 0.6
      }
    }
  }

  component PageHeader: Item {
    id: ph
    property string title: ""
    property bool checked: false
    signal toggled()
    width: parent ? parent.width : 0
    height: 34
    Rectangle {
      id: back
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: 26
      height: 26
      radius: 13
      color: backMouse.containsMouse ? Util.alpha(Color.foreground, 0.14) : "transparent"
      Glyph { anchors.centerIn: parent; text: "󰅁"; font.pixelSize: 14 }
      MouseArea {
        id: backMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openPage("")
      }
    }
    Label {
      anchors.left: back.right
      anchors.leftMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      text: ph.title
      font.pixelSize: 15
      font.weight: Font.Bold
    }
    Switch {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: ph.checked
      onToggled: ph.toggled()
    }
  }

  component FooterLink: Rectangle {
    id: fl
    property string title: ""
    signal clicked()
    width: parent ? parent.width : 0
    height: 30
    radius: 8
    color: flMouse.containsMouse ? Util.alpha(Color.foreground, 0.08) : "transparent"
    Label {
      anchors.left: parent.left
      anchors.leftMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      text: fl.title
      font.weight: Font.Normal
    }
    MouseArea {
      id: flMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: fl.clicked()
    }
  }

  component PillSlider: Item {
    id: slider
    property real value: 0          // 0..1
    property string icon: ""
    property bool dragging: mouse.pressed
    signal moved(real value)
    signal iconClicked()
    height: 24

    Rectangle {
      id: track
      anchors.fill: parent
      radius: height / 2
      color: Util.alpha(Color.foreground, 0.16)
      clip: true

      Rectangle {
        height: parent.height
        width: Math.max(track.height, track.width * Math.max(0, Math.min(1, slider.value)))
        radius: height / 2
        color: Util.alpha(Color.foreground, 0.92)
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      anchors.leftMargin: 26
      cursorShape: Qt.PointingHandCursor
      function apply(x) {
        var v = Math.max(0, Math.min(1, (x + 26) / track.width))
        slider.moved(v)
      }
      onPressed: function(e) { apply(e.x) }
      onPositionChanged: function(e) { if (pressed) apply(e.x) }
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      text: slider.icon
      color: slider.value > 0.06 ? Color.background : Color.foreground
      font.family: root.iconFont
      font.pixelSize: 14
      MouseArea {
        anchors.fill: parent
        anchors.margins: -4
        cursorShape: Qt.PointingHandCursor
        onClicked: slider.iconClicked()
      }
    }
  }

  component PowerButton: Column {
    id: pb
    property string icon: ""
    property string title: ""
    property bool confirm: false
    property bool armed: false
    signal activated()
    spacing: 5
    width: root.showLock ? 64 : 70

    Timer { id: disarm; interval: 3000; onTriggered: pb.armed = false }

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: 40
      height: 40
      radius: 20
      color: pb.armed ? Color.urgent : Util.alpha(Color.foreground, pbMouse.containsMouse ? 0.24 : 0.14)
      Behavior on color { ColorAnimation { duration: 120 } }
      Glyph {
        anchors.centerIn: parent
        text: pb.icon
        font.pixelSize: 18
      }
      MouseArea {
        id: pbMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          root.interacted()
          if (pb.confirm && !pb.armed) { pb.armed = true; disarm.restart(); return }
          pb.armed = false
          pb.activated()
        }
      }
    }
    Sub {
      anchors.horizontalCenter: parent.horizontalCenter
      text: pb.armed ? "Click again" : pb.title
      color: pb.armed ? Color.foreground : Util.alpha(Color.foreground, 0.7)
    }
  }

  // ── Panel ──────────────────────────────────────────────────────────
  Rectangle {
    id: panel
    width: parent.width
    height: (root.page === "wifi" ? wifiPage.implicitHeight
           : root.page === "bluetooth" ? btPage.implicitHeight
           : root.page === "sound" ? soundPage.implicitHeight
           : root.page === "windows" ? winLoader.implicitHeight
           : mainPage.implicitHeight) + 24
    radius: 20
    color: root.chromeless ? "transparent" : Util.alpha(Color.background, root.panelAlpha)
    border.color: Util.alpha(Color.foreground, 0.14)
    border.width: root.chromeless ? 0 : 1
    clip: true
    transformOrigin: Item.TopRight
    opacity: root.opened ? 1 : 0
    scale: root.opened || root.chromeless ? 1 : 0.94
    Behavior on opacity { NumberAnimation { duration: root.chromeless ? 200 : 140; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    // Swallow clicks on the panel's empty space so they don't close it.
    MouseArea { anchors.fill: parent; onClicked: root.interacted() }

    // ── Main page ──
    Column {
      id: mainPage
      x: root.page === "" ? 12 : -parent.width
      y: 12
      width: parent.width - 24
      spacing: 10
      opacity: root.page === "" ? 1 : 0
      visible: opacity > 0
      Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      Behavior on opacity { NumberAnimation { duration: 160 } }

      Row {
        width: parent.width
        spacing: 10

        Tile {
          width: (parent.width - 10) * 0.56
          height: 122
          Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6
            // The two rows split the tile evenly (it is as tall as the two
            // tiles beside it), so nothing is left over under Bluetooth.
            ToggleRow {
              width: parent.width
              height: (parent.height - parent.spacing) / 2
              icon: root.wifiOn ? "󰖩" : "󰖪"
              title: "Wi-Fi"
              subtitle: !root.wifiOn ? "Off" : (root.ssid.length > 0 ? root.ssid : "Not connected")
              on: root.wifiOn
              onToggled: { Networking.wifiEnabled = !Networking.wifiEnabled; root.interacted() }
              onExpand: root.openPage("wifi")
            }
            ToggleRow {
              width: parent.width
              height: (parent.height - parent.spacing) / 2
              icon: root.bluetoothOn ? "󰂯" : "󰂲"
              title: "Bluetooth"
              subtitle: !root.adapter ? "Unavailable"
                : !root.bluetoothOn ? "Off"
                : root.connectedBtCount > 0 ? root.connectedBtCount + " connected" : "On"
              on: root.bluetoothOn
              onToggled: if (root.adapter) root.run("omarchy-bluetooth-power " + (root.bluetoothOn ? "off" : "on"))
              onExpand: if (root.adapter) root.openPage("bluetooth")
            }
          }
        }

        Column {
          width: (parent.width - 10) * 0.44
          spacing: 10

          Tile {
            width: parent.width
            height: 56
            color: Util.alpha(Color.foreground, kbMouse.containsMouse ? 0.13 : 0.08)
            Column {
              anchors.fill: parent
              anchors.margins: 10
              spacing: 1
              Row {
                spacing: 7
                Glyph { anchors.verticalCenter: parent.verticalCenter; text: "󰌌"; font.pixelSize: 14 }
                Label { anchors.verticalCenter: parent.verticalCenter; text: root.layoutShort || "—" }
              }
              Sub { width: parent.width; text: root.layoutFull || "Keyboard" }
            }
            MouseArea {
              id: kbMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.run("hyprctl switchxkblayout all next")
            }
          }

          Tile {
            width: parent.width
            height: 56
            visible: !dndTile.visible
            Column {
              anchors.fill: parent
              anchors.margins: 10
              spacing: 1
              Row {
                spacing: 7
                Glyph { anchors.verticalCenter: parent.verticalCenter; text: root.batteryPercent >= 0 ? root.batteryIcon : "󰚥"; font.pixelSize: 14 }
                Label { anchors.verticalCenter: parent.verticalCenter; text: root.batteryPercent >= 0 ? root.batteryPercent + "%" : "AC" }
              }
              Sub { width: parent.width; text: root.batteryPercent < 0 ? "Power" : (root.charging ? "Charging" : "Battery") }
            }
          }

          // No battery (the iMac): the slot is Do Not Disturb instead of a
          // tile that could only ever say "AC". Bar copy only.
          Tile {
            id: dndTile
            width: parent.width
            height: 56
            visible: root.showLock && root.batteryPercent < 0
            color: root.dnd ? root.accent : Util.alpha(Color.foreground, dndMouse.containsMouse ? 0.13 : 0.08)
            Behavior on color { ColorAnimation { duration: 140 } }
            Column {
              anchors.fill: parent
              anchors.margins: 10
              spacing: 1
              Row {
                spacing: 7
                Glyph { anchors.verticalCenter: parent.verticalCenter; text: root.dnd ? "󰂛" : "󰂚"; font.pixelSize: 14; color: root.dnd ? root.onAccent : Color.foreground }
                Label { anchors.verticalCenter: parent.verticalCenter; text: "Do not disturb"; color: root.dnd ? root.onAccent : Color.foreground }
              }
              Sub { width: parent.width; color: root.dnd ? root.onAccent : Util.alpha(Color.foreground, 0.6); text: root.dnd ? "On" : "Off" }
            }
            MouseArea {
              id: dndMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { root.dnd = !root.dnd; Quickshell.execDetached(["omarchy-shell", "notifications", "setDnd", root.dnd ? "on" : "off"]); root.interacted() }
            }
          }
        }
      }

      // Laptop (has a battery, so the battery tile keeps its slot): Do Not
      // Disturb gets its own row here instead (N-U7). Bar copy only. On a
      // machine without a battery the switch lives in the battery slot above.
      Tile {
        width: parent.width
        height: 46
        visible: root.showLock && root.batteryPercent >= 0
        color: Util.alpha(Color.foreground, dndRowMouse.containsMouse ? 0.13 : 0.08)
        MouseArea {
          id: dndRowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { root.dnd = !root.dnd; Quickshell.execDetached(["omarchy-shell", "notifications", "setDnd", root.dnd ? "on" : "off"]); root.interacted() }
        }
        Row {
          anchors.left: parent.left
          anchors.leftMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          spacing: 9
          Glyph { anchors.verticalCenter: parent.verticalCenter; text: root.dnd ? "󰂛" : "󰂚"; font.pixelSize: 15; color: root.dnd ? root.accent : Color.foreground }
          Label { anchors.verticalCenter: parent.verticalCenter; text: "Do not disturb" }
        }
        Switch {
          anchors.right: parent.right
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          checked: root.dnd
          onToggled: { root.dnd = !root.dnd; Quickshell.execDetached(["omarchy-shell", "notifications", "setDnd", root.dnd ? "on" : "off"]); root.interacted() }
        }
      }

      Tile {
        width: parent.width
        height: 66
        visible: root.brightness >= 0
        Column {
          anchors.fill: parent
          anchors.margins: 11
          spacing: 8
          Item {
            width: parent.width
            height: displayLabel.implicitHeight
            Label { id: displayLabel; text: "Display" }
            // Auto brightness from the ambient light sensor (bar copy, and
            // only on a machine that has the sensor and the helper script).
            Row {
              visible: root.showLock && root.hasLightSensor
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: 7
              Sub { anchors.verticalCenter: parent.verticalCenter; text: "Auto" }
              Switch {
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 20
                radius: 10
                checked: root.autoBright
                onToggled: root.setAutoBright(!root.autoBright)
              }
            }
          }
          PillSlider {
            id: brightnessSlider
            width: parent.width
            icon: "󰃠"
            value: root.brightness / 100
            onMoved: function(v) {
              // A hand on the slider means "I'll set it myself".
              if (root.autoBright) root.setAutoBright(false)
              var pct = Math.max(5, Math.round(v * 100))
              root.brightness = pct
              brightnessWriter.pending = pct
              if (!brightnessWriter.running) brightnessWriter.start()
              root.interacted()
            }
          }
        }
      }

      Tile {
        width: parent.width
        height: 66
        Column {
          anchors.fill: parent
          anchors.margins: 11
          spacing: 8
          // Bar copy only: the header slides to the Sound page (outputs,
          // inputs, per-app volume and the iMac's Fix Sound button).
          Item {
            width: parent.width
            height: soundLabel.implicitHeight
            Label { id: soundLabel; text: "Sound" + (root.sink ? "" : " — no output") }
            Glyph {
              visible: root.showLock
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "󰅂"
              font.pixelSize: 12
              opacity: soundMouse.containsMouse ? 0.8 : 0.35
            }
            MouseArea {
              id: soundMouse
              anchors.fill: parent
              enabled: root.showLock
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openPage("sound")
            }
          }
          PillSlider {
            width: parent.width
            icon: root.muted ? "󰝟" : (root.volume < 0.34 ? "󰕿" : root.volume < 0.67 ? "󰖀" : "󰕾")
            value: root.muted ? 0 : root.volume
            onMoved: function(v) {
              if (!root.sink || !root.sink.audio) return
              root.sink.audio.muted = false
              root.sink.audio.volume = v
              root.interacted()
            }
            onIconClicked: {
              if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
              root.interacted()
            }
          }
        }
      }

      // Window look (bar copy only): slides to the nasaq.windows settings.
      Tile {
        width: parent.width
        height: 52
        visible: root.showLock
        color: Util.alpha(Color.foreground, winMouse.containsMouse ? 0.13 : 0.08)
        RoundIcon {
          id: winIcon
          anchors.left: parent.left
          anchors.leftMargin: 11
          anchors.verticalCenter: parent.verticalCenter
          icon: "󰖲"
          on: false
          clickable: false
        }
        Column {
          anchors.left: winIcon.right
          anchors.leftMargin: 9
          anchors.right: winChevron.left
          anchors.verticalCenter: parent.verticalCenter
          Label { width: parent.width; text: "Windows" }
          Sub { width: parent.width; text: "Transparency, blur, shadows, shape" }
        }
        Glyph {
          id: winChevron
          anchors.right: parent.right
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          text: "󰅂"
          font.pixelSize: 12
          opacity: winMouse.containsMouse ? 0.8 : 0.35
        }
        MouseArea {
          id: winMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openPage("windows")
        }
      }

      // Power mode: Power Saver / Balanced / Performance
      Tile {
        width: parent.width
        height: 78
        visible: root.powerProfiles.length > 1
        Column {
          anchors.fill: parent
          anchors.margins: 11
          spacing: 8
          Item {
            width: parent.width
            height: 16
            Label { anchors.left: parent.left; text: "Power mode" }
            Sub {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.charging || root.batteryPercent < 0 ? "Saved for: plugged in" : "Saved for: battery"
            }
          }
          Row {
            width: parent.width
            spacing: 6
            Repeater {
              model: [
                { key: "power-saver", icon: "󰌪", title: "Saver" },
                { key: "balanced", icon: "󰾅", title: "Balanced" },
                { key: "performance", icon: "󰓅", title: "Performance" }
              ]
              delegate: Rectangle {
                id: modeBtn
                required property var modelData
                readonly property bool current: (root.pendingProfile || root.powerProfile) === modelData.key
                visible: root.powerProfiles.indexOf(modelData.key) !== -1
                width: (parent.width - 12) / 3
                height: 30
                radius: 15
                color: current ? root.accent : Util.alpha(Color.foreground, modeMouse.containsMouse ? 0.16 : 0.08)
                Behavior on color { ColorAnimation { duration: 140 } }
                Row {
                  anchors.centerIn: parent
                  spacing: 5
                  Glyph { anchors.verticalCenter: parent.verticalCenter; text: modelData.icon; font.pixelSize: 13; color: modeBtn.current ? root.onAccent : Color.foreground }
                  Sub { anchors.verticalCenter: parent.verticalCenter; text: modelData.title; color: modeBtn.current ? root.onAccent : Color.foreground; font.weight: Font.DemiBold }
                }
                MouseArea {
                  id: modeMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (parent.current) return
                    root.pendingProfile = modelData.key
                    profileClear.restart()
                    Quickshell.execDetached(["omarchy-powerprofiles-set", "autodetect", modelData.key])
                    root.interacted()
                    refreshSoon.restart()
                  }
                }
              }
            }
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.showLock ? 8 : 22
        topPadding: 2
        PowerButton {
          visible: root.showLock
          icon: "󰌾"
          title: "Lock"
          onActivated: { root.closeRequested(); root.run("omarchy-system-lock") }
        }
        PowerButton { icon: "󰒲"; title: "Sleep"; onActivated: { root.closeRequested(); root.run("systemctl suspend") } }
        PowerButton { icon: "󰜉"; title: "Restart"; confirm: true; onActivated: root.run("omarchy-system-reboot") }
        PowerButton { icon: "󰐥"; title: "Shut down"; confirm: true; onActivated: root.run("omarchy-system-shutdown") }
      }

      // Bar copy only (never on the lock screen): the full NASAQ Settings window.
      FooterLink {
        visible: root.showLock
        title: "NASAQ Settings…"
        onClicked: { root.closeRequested(); Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "nasaq.settings", "{}"]) }
      }
    }

    // ── Wi-Fi page ──
    Column {
      id: wifiPage
      x: root.page === "wifi" ? 12 : parent.width
      y: 12
      width: parent.width - 24
      spacing: 6
      opacity: root.page === "wifi" ? 1 : 0
      visible: opacity > 0
      Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      Behavior on opacity { NumberAnimation { duration: 160 } }

      PageHeader {
        title: "Wi-Fi"
        checked: root.wifiOn
        onToggled: { Networking.wifiEnabled = !Networking.wifiEnabled; root.interacted() }
      }
      Divider { width: parent.width }

      // Live connection card: rates, latency, radio details, speed test.
      Tile {
        width: parent.width
        visible: root.netConnected
        height: statsCol.implicitHeight + 20
        Column {
          id: statsCol
          x: 10
          y: 10
          width: parent.width - 20
          spacing: 8

          Row {
            width: parent.width
            Repeater {
              model: [
                { icon: "󰇚", label: "Download", value: root.formatRate(root.downRate) },
                { icon: "󰕒", label: "Upload", value: root.formatRate(root.upRate) },
                { icon: "󰓅", label: "Ping", value: root.netInfo.internet_ping_ms ? Math.round(parseFloat(root.netInfo.internet_ping_ms)) + " ms" : "—" }
              ]
              delegate: Column {
                required property var modelData
                width: statsCol.width / 3
                spacing: 1
                Sub { text: modelData.icon + " " + modelData.label; font.family: root.iconFont }
                Label { text: modelData.value; font.pixelSize: 14 }
              }
            }
          }

          Sub {
            width: parent.width
            text: {
              var i = root.netInfo, parts = []
              if (i.signal_dbm) parts.push(i.signal_dbm + " dBm")
              if (i.freq) parts.push((parseFloat(i.freq) >= 5900 ? "6" : parseFloat(i.freq) >= 4900 ? "5" : "2.4") + " GHz")
              if (i.bitrate) parts.push(i.bitrate.replace("MBit/s", "Mbps"))
              if (i.ip) parts.push(i.ip)
              return parts.join("  ·  ")
            }
          }

          Rectangle {
            visible: root.showLock
            width: parent.width
            height: 28
            radius: 8
            color: Util.alpha(Color.foreground, stMouse.containsMouse ? 0.18 : 0.10)
            Label {
              anchors.centerIn: parent
              text: "󰓅  Speed Test"
              font.family: root.iconFont
              font.pixelSize: 12
            }
            MouseArea {
              id: stMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.runSpeedTest()
            }
          }
        }
      }

      // DNS provider pills (bar only: changing system DNS from a locked
      // screen isn't something a passer-by should be able to do).
      Item {
        width: parent.width
        height: 30
        visible: root.showLock
        Sub {
          anchors.left: parent.left
          anchors.leftMargin: 4
          anchors.verticalCenter: parent.verticalCenter
          text: "DNS"
          font.weight: Font.DemiBold
        }
        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 4
          Repeater {
            model: ["DHCP", "Cloudflare", "Google", "Custom"]
            delegate: Rectangle {
              required property string modelData
              readonly property bool current: (root.pendingDns || root.dnsProvider) === modelData
              width: dnsText.implicitWidth + 14
              height: 24
              radius: 12
              color: current ? root.accent : Util.alpha(Color.foreground, dnsMouse.containsMouse ? 0.18 : 0.10)
              opacity: root.pendingDns && root.pendingDns === modelData ? 0.7 : 1
              Sub {
                id: dnsText
                anchors.centerIn: parent
                text: modelData
                color: parent.current ? root.onAccent : Color.foreground
              }
              MouseArea {
                id: dnsMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (!parent.current || modelData === "Custom") root.setDns(modelData)
              }
            }
          }
        }
      }
      Divider { width: parent.width; visible: root.netConnected || root.showLock }

      Sub {
        width: parent.width
        visible: !root.wifiOn
        text: "Wi-Fi is turned off."
        leftPadding: 4
        topPadding: 4
        bottomPadding: 4
      }

      Flickable {
        id: wifiList
        width: parent.width
        visible: root.wifiOn
        height: Math.min(wifiColumn.implicitHeight, 330)
        contentHeight: wifiColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: wifiColumn
          width: parent.width
          spacing: 2

          ListRow {
            visible: root.currentNetwork !== null
            icon: root.signalIcon(root.wifiSignal)
            on: true
            title: root.ssid
            trailingIcon: root.isSecured(root.currentNetwork) ? "󰌾" : ""
            onClicked: root.joinNetwork(root.currentNetwork)
          }

          SectionTitle { visible: root.knownNetworks.length > 0; text: "Known networks" }
          Repeater {
            model: root.knownNetworks
            delegate: NetworkRow { required property var modelData; net: modelData }
          }

          SectionTitle { visible: root.otherNetworks.length > 0; text: "Other networks" }
          Repeater {
            model: root.otherNetworks
            delegate: NetworkRow { required property var modelData; net: modelData }
          }

          Sub {
            visible: root.networks.length === 0
            text: "Searching for networks…"
            leftPadding: 4
            topPadding: 6
            bottomPadding: 6
          }
        }
      }

      Divider { width: parent.width; visible: root.showLock }
      FooterLink {
        visible: root.showLock
        title: "Wi-Fi settings…"
        onClicked: { root.closeRequested(); Quickshell.execDetached(["omarchy-shell", "omarchy.network", "open"]) }
      }
    }

    // ── Bluetooth page ──
    Column {
      id: btPage
      x: root.page === "bluetooth" ? 12 : parent.width
      y: 12
      width: parent.width - 24
      spacing: 6
      opacity: root.page === "bluetooth" ? 1 : 0
      visible: opacity > 0
      Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      Behavior on opacity { NumberAnimation { duration: 160 } }

      PageHeader {
        title: "Bluetooth"
        checked: root.bluetoothOn
        onToggled: root.run("omarchy-bluetooth-power " + (root.bluetoothOn ? "off" : "on"))
      }
      Divider { width: parent.width }

      Sub {
        width: parent.width
        visible: !root.bluetoothOn
        text: "Bluetooth is turned off."
        leftPadding: 4
        topPadding: 4
        bottomPadding: 4
      }

      Flickable {
        width: parent.width
        visible: root.bluetoothOn
        height: Math.min(btColumn.implicitHeight, 330)
        contentHeight: btColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: btColumn
          width: parent.width
          spacing: 2

          SectionTitle { visible: root.pairedDevices.length > 0; text: "Devices" }
          Repeater {
            model: root.pairedDevices
            delegate: ListRow {
              required property var modelData
              icon: root.deviceIcon(modelData)
              on: modelData.connected
              title: root.deviceName(modelData) || modelData.address
              busy: root.pendingAddress === modelData.address && !modelData.connected
                    || modelData.state === BluetoothDeviceState.Connecting
              trailing: modelData.connected && modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "%" : ""
              onClicked: root.toggleDevice(modelData)
            }
          }

          SectionTitle { text: "Nearby devices" }
          Repeater {
            model: root.nearbyDevices
            delegate: ListRow {
              required property var modelData
              icon: root.deviceIcon(modelData)
              title: root.deviceName(modelData)
              busy: root.pendingAddress === modelData.address || modelData.pairing === true
              trailing: "Connect"
              onClicked: root.toggleDevice(modelData)
            }
          }
          Sub {
            visible: root.nearbyDevices.length === 0
            text: "Searching…"
            leftPadding: 4
            topPadding: 2
            bottomPadding: 6
          }
        }
      }

      Divider { width: parent.width; visible: root.showLock }
      FooterLink {
        visible: root.showLock
        title: "Bluetooth settings…"
        onClicked: { root.closeRequested(); Quickshell.execDetached(["omarchy-shell", "omarchy.bluetooth", "open"]) }
      }
    }

    // ── Windows page (nasaq.windows/WindowLook.qml) ──
    // Loaded only in the bar copy and only while the page shows: the lock
    // screen never creates it, and a missing nasaq.windows folder costs this
    // page, not the control center or the lock. Unloading it also makes it
    // write its pending NASAQ Settings save.
    Loader {
      id: winLoader
      // Kept alive while an Undo is pending. Tracked in a plain property (set
      // from the item's signal) because binding `active` to `item.undo` is a
      // binding loop: active decides whether item exists.
      property bool undoPending: false
      active: root.showLock && (root.page === "windows" || winKeep.running || undoPending)
      source: active ? Qt.resolvedUrl("../nasaq.windows/WindowLook.qml") : ""
      onItemChanged: if (!item) undoPending = false
      Connections {
        target: winLoader.item
        ignoreUnknownSignals: true
        function onUndoChanged() { winLoader.undoPending = winLoader.item !== null && winLoader.item.undo !== null }
      }
      x: root.page === "windows" ? 12 : parent.width
      y: 12
      width: parent.width - 24
      opacity: root.page === "windows" ? 1 : 0
      visible: opacity > 0
      onLoaded: item.showBack = true
      Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      Behavior on opacity { NumberAnimation { duration: 160 } }
    }
    // Keeps the page alive while it slides out.
    Timer { id: winKeep; interval: 400 }
    Connections {
      target: winLoader.item
      ignoreUnknownSignals: true
      function onBackRequested() { root.openPage("") }
    }

    // ── Sound page ──
    Column {
      id: soundPage
      x: root.page === "sound" ? 12 : parent.width
      y: 12
      width: parent.width - 24
      spacing: 6
      opacity: root.page === "sound" ? 1 : 0
      visible: opacity > 0
      Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      Behavior on opacity { NumberAnimation { duration: 160 } }

      PageHeader {
        title: "Sound"
        checked: !root.muted
        onToggled: { if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted; root.interacted() }
      }
      Divider { width: parent.width }

      Flickable {
        width: parent.width
        height: Math.min(soundColumn.implicitHeight, 420)
        contentHeight: soundColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: soundColumn
          width: parent.width
          spacing: 2

          SectionTitle { text: "Output" }
          PillSlider {
            width: parent.width
            icon: root.volumeIcon(root.volume, root.muted)
            value: root.muted ? 0 : root.volume
            onMoved: function(v) {
              if (!root.sink || !root.sink.audio) return
              root.sink.audio.muted = false
              root.sink.audio.volume = v
              root.interacted()
            }
            onIconClicked: { if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted; root.interacted() }
          }
          Item { width: 1; height: 4 }
          Repeater {
            model: root.shownSinks
            delegate: ListRow {
              required property var modelData
              icon: AudioModel.sinkGlyph(modelData)
              on: root.sink === modelData
              title: root.deviceLabel(modelData, true)
              trailingIcon: root.sink === modelData ? "󰄬" : ""
              onClicked: root.setDefaultSink(modelData)
            }
          }

          SectionTitle { visible: root.shownSources.length > 0; text: "Input" }
          PillSlider {
            visible: !!root.source
            width: parent.width
            icon: root.inputMuted ? "󰍭" : "󰍬"
            value: root.inputMuted ? 0 : root.inputVolume
            onMoved: function(v) {
              if (!root.source || !root.source.audio) return
              root.source.audio.muted = false
              root.source.audio.volume = v
              root.interacted()
            }
            onIconClicked: { if (root.source && root.source.audio) root.source.audio.muted = !root.source.audio.muted; root.interacted() }
          }
          Item { width: 1; height: 4; visible: root.shownSources.length > 0 }
          Repeater {
            model: root.shownSources
            delegate: ListRow {
              required property var modelData
              icon: AudioModel.sourceGlyph(modelData)
              on: root.source === modelData
              title: root.deviceLabel(modelData, false)
              trailingIcon: root.source === modelData ? "󰄬" : ""
              onClicked: root.setDefaultSource(modelData)
            }
          }

          SectionTitle { visible: root.shownStreams.length > 0; text: "Apps" }
          Repeater {
            model: root.shownStreams
            delegate: Column {
              required property var modelData
              width: soundColumn.width
              spacing: 4
              topPadding: 2
              bottomPadding: 4
              Sub {
                width: parent.width
                leftPadding: 4
                text: AudioModel.friendlyStreamLabel(AudioModel.rawStreamLabel(modelData)) || "App"
              }
              PillSlider {
                width: parent.width
                readonly property bool m: !!modelData.audio && modelData.audio.muted
                readonly property real v: modelData.audio ? modelData.audio.volume : 0
                icon: root.volumeIcon(v, m)
                value: m ? 0 : v
                onMoved: function(val) {
                  if (!modelData.audio) return
                  modelData.audio.muted = false
                  modelData.audio.volume = val
                  root.interacted()
                }
                onIconClicked: { if (modelData.audio) modelData.audio.muted = !modelData.audio.muted; root.interacted() }
              }
            }
          }
        }
      }

      Divider { width: parent.width; visible: root.hasFixSound }
      // iMac speakers sometimes go silent; ~/.local/bin/fix-sound rebinds the
      // card (it stops and restarts the shell around it).
      Rectangle {
        visible: root.hasFixSound
        width: parent.width
        height: 34
        radius: 17
        color: Util.alpha(Color.foreground, fixMouse.containsMouse ? 0.18 : 0.10)
        Row {
          anchors.centerIn: parent
          spacing: 8
          Glyph { anchors.verticalCenter: parent.verticalCenter; text: "󰖷"; font.pixelSize: 14 }
          Label { anchors.verticalCenter: parent.verticalCenter; text: "Fix speakers" }
        }
        MouseArea {
          id: fixMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { root.closeRequested(); Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/fix-sound"]) }
        }
      }
      Sub {
        visible: root.hasFixSound
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
        text: "Use when the speakers go silent."
      }
    }
  }

  // Wi-Fi network row with an inline password prompt for new secured
  // networks.
  component NetworkRow: Column {
    id: nr
    property var net: null
    readonly property bool prompting: !!net && root.promptSsid === net.name
    width: parent ? parent.width : 0
    spacing: 4

    onPromptingChanged: if (prompting) Qt.callLater(function() { pwInput.forceActiveFocus() })

    ListRow {
      width: parent.width
      icon: root.signalIcon(Math.round((nr.net ? nr.net.signalStrength : 0) * 100))
      title: nr.net ? nr.net.name : ""
      busy: !!nr.net && (root.pendingSsid === nr.net.name || nr.net.stateChanging)
      trailing: !!nr.net && root.failedSsid === nr.net.name ? "Failed" : ""
      trailingIcon: root.isSecured(nr.net) ? "󰌾" : ""
      onClicked: root.joinNetwork(nr.net)
    }

    Rectangle {
      visible: nr.prompting
      width: parent.width
      height: 34
      radius: 8
      color: Util.alpha(Color.foreground, 0.12)
      border.color: Util.alpha(Color.foreground, pwInput.activeFocus ? 0.35 : 0.12)

      TextInput {
        id: pwInput
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 64
        verticalAlignment: TextInput.AlignVCenter
        echoMode: TextInput.Password
        passwordMaskDelay: 0
        color: Color.foreground
        selectionColor: Util.alpha(Color.accent, 0.45)
        font.family: root.textFont
        font.pixelSize: 13
        clip: true
        onAccepted: { root.submitPassword(nr.net, text); text = "" }
        Keys.onEscapePressed: { text = ""; root.promptSsid = ""; root.interacted() }
        onTextChanged: root.interacted()
      }
      Text {
        anchors.fill: pwInput
        verticalAlignment: Text.AlignVCenter
        visible: pwInput.text.length === 0
        text: "Password"
        color: Util.alpha(Color.foreground, 0.45)
        font.family: root.textFont
        font.pixelSize: 13
      }
      Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        width: 54
        height: 26
        radius: 6
        color: pwInput.text.length > 0 ? root.accent : Util.alpha(Color.foreground, 0.15)
        Label { anchors.centerIn: parent; text: "Join"; font.pixelSize: 12; color: pwInput.text.length > 0 ? root.onAccent : Color.foreground }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: pwInput.accepted()
        }
      }
    }

    Connections {
      target: nr.net
      function onConnectionFailed(reason) {
        if (!nr.net || root.pendingSsid !== nr.net.name) return
        root.pendingSsid = ""
        root.failedSsid = nr.net.name
        // Wrong password: ask again.
        if (root.isSecured(nr.net)) root.promptSsid = nr.net.name
      }
      function onConnectedChanged() {
        if (nr.net && nr.net.connected && root.pendingSsid === nr.net.name) {
          root.pendingSsid = ""
          root.failedSsid = ""
        }
      }
    }
  }
}
