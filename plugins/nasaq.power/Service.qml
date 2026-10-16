import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Hyprland
import "../nasaq.commons" as Nasaq

// NASAQ: power behaviour on top of power-profiles-daemon.
//
// • Low Power Mode turns itself on when the battery drops to `lowPowerAt`
//   (20 %) while unplugged, and off again once the charger is connected
//   (Omarchy's battery service then restores the plugged-in profile).
// • Whatever the profile, its "personality" is applied:
//     Saver       – no blur, no animations, brightness capped (50 %, 30 % under 10 %)
//     Balanced    – normal look; on battery the lock screen turns the display off
//                   within 10 min (nasaq.lock reads `displayCapMs`)
//     Performance – everything on, no caps
// • The island announces each change.
// • Awake for media: while something plays (any MPRIS player: browser, Spotify,
//   mpv) or a window is fullscreen (a film, a game), a Wayland idle inhibitor
//   keeps the screensaver and the auto-lock away. It never touches Omarchy's
//   own Stay awake switch. Settings › System › "Stay awake while media plays".
// • Game mode (SUPER + ALT + G, Quick Settings): animations off; windows opaque,
//   unblurred and shadowless (the desktop widgets and panels keep their glass);
//   notifications quiet, hot corners off. Off puts the config back.
//   State in ~/.local/state/nasaq/gamemode ("1"/"0") so it survives a shell
//   restart and the notification service and hot corners can read it.
// Settings: ~/.config/omarchy/nasaq/power.json (all keys optional).
Item {
  id: root

  property var shell: null
  property string omarchyPath: ""

  property var config: ({ lowPowerAt: 20, criticalAt: 10, saverBrightness: 50, criticalBrightness: 30 })

  readonly property var battery: UPower.displayDevice
  readonly property bool hasBattery: !!battery && battery.isPresent
  readonly property bool onBattery: hasBattery && UPower.onBattery
  readonly property int percent: hasBattery ? Math.round(Number(battery.percentage || 0) * 100) : 100

  property string profile: ""          // power-saver | balanced | performance
  property bool autoLowPower: false      // we switched to power-saver ourselves
  property string profileBeforeLow: ""
  property int brightnessBeforeCap: -1
  property int brightnessCappedTo: -1
  property string appliedPersonality: ""
  property bool loaded: false

  // A function, not a binding: profile change handlers run before bindings
  // that depend on profile have updated, so a binding would lag one step.
  function isSaver() { return profile === "power-saver" }
  readonly property bool saver: profile === "power-saver"

  // ── State that must survive shell restarts ───────────────────────
  FileView {
    id: stateFile
    path: Quickshell.env("HOME") + "/.local/state/nasaq/power.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var st = JSON.parse(text())
        root.autoLowPower = !!st.autoLowPower
        root.profileBeforeLow = st.profileBeforeLow || ""
        root.brightnessBeforeCap = st.brightnessBeforeCap === undefined ? -1 : st.brightnessBeforeCap
        root.brightnessCappedTo = st.brightnessCappedTo === undefined ? -1 : st.brightnessCappedTo
      } catch (e) {}
      root.loaded = true
    }
    onLoadFailed: root.loaded = true
  }
  function saveState() {
    stateFile.setText(JSON.stringify({
      autoLowPower: autoLowPower, profileBeforeLow: profileBeforeLow,
      brightnessBeforeCap: brightnessBeforeCap, brightnessCappedTo: brightnessCappedTo
    }) + "\n")
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/nasaq/power.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.config = Object.assign({}, root.config, JSON.parse(text())) } catch (e) {} }
  }

  // ── Watch the profile ────────────────────────────────────────────
  Process {
    id: profileProc
    // Polled every few seconds, so read over D-Bus: powerprofilesctl is Python and
    // ~28k runs a day made its intermittent exit segfault show up (2026-10-07).
    command: ["bash", "-c", "busctl get-property net.hadess.PowerProfiles /net/hadess/PowerProfiles net.hadess.PowerProfiles ActiveProfile 2>/dev/null | sed -E 's/^s \"(.*)\"$/\\1/'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = String(text || "").trim()
        if (p && p !== root.profile) root.profile = p
      }
    }
  }
  // A battery can drain into Low Power Mode at any moment, so a laptop is
  // checked every 3 s. A desktop only changes mode when the user picks one.
  Timer {
    interval: root.hasBattery ? 3000 : 30000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!profileProc.running) profileProc.running = true
  }

  function setProfile(p) {
    Quickshell.execDetached(["busctl", "set-property", "net.hadess.PowerProfiles", "/net/hadess/PowerProfiles",
      "net.hadess.PowerProfiles", "ActiveProfile", "s", p])
    profile = p
  }

  function announce(title, subtitle) {
    Quickshell.execDetached(["omarchy-shell", "nasaq.island", "alert", title, subtitle || ""])
  }

  // ── Low Power Mode on/off ────────────────────────────────────────
  function evaluate() {
    if (!loaded || !profile) return
    var lowAt = config.lowPowerAt || 20
    if (onBattery && percent <= lowAt && !isSaver() && !autoLowPower) {
      profileBeforeLow = profile
      autoLowPower = true
      saveState()
      setProfile("power-saver")
      announce("Low Power Mode", "Battery " + percent + "% — display dimmed, effects off")
    } else if (autoLowPower && !onBattery) {
      // Plugged in: hand back to Omarchy, which restores the plugged-in profile.
      autoLowPower = false
      saveState()
      if (isSaver() && profileBeforeLow) setProfile(profileBeforeLow)
      profileBeforeLow = ""
      announce("Low Power Mode off", "Charger connected")
    } else if (autoLowPower && !isSaver()) {
      // the user picked another mode; respect it.
      autoLowPower = false
      profileBeforeLow = ""
      saveState()
    }
    applyPersonality()
  }

  onProfileChanged: evaluate()
  onOnBatteryChanged: { evaluate(); checkHibernate() }
  onPercentChanged: { evaluate(); if (isSaver()) applyBrightnessCap(); checkHibernate() }
  onLoadedChanged: { evaluate(); checkHibernate() }

  // ── Hibernate before the battery dies ─────────────────────────────
  // On battery at power.hibernateAt % (default 3): a critical alert and a
  // 30 s countdown in the island, then systemctl hibernate, so nothing is
  // lost to a sudden power-off. Plugging in the charger cancels it. Once per
  // discharge: it re-arms when the charger connects or the battery climbs
  // three points above the threshold. Settings › System.
  readonly property int hibernateAt: Math.max(1, Math.min(15, Number(Nasaq.Settings.get("power.hibernateAt", 3)) || 3))
  readonly property bool hibernateEnabled: Nasaq.Settings.get("power.hibernateOnCritical", true) !== false
  property bool hibernateArmed: true
  property int hibernateLeft: 0
  property bool hibernateDrill: false
  function checkHibernate() {
    if (!loaded || !hasBattery) return
    if (!onBattery) {
      if (hibernateTick.running) cancelHibernate("Charger connected")
      hibernateArmed = true
      return
    }
    if (percent > hibernateAt + 3) hibernateArmed = true
    if (!hibernateEnabled || !hibernateArmed || hibernateTick.running) return
    if (percent > 0 && percent <= hibernateAt) startHibernateCountdown(false)
  }
  function startHibernateCountdown(drill) {
    hibernateArmed = false
    hibernateDrill = drill
    hibernateLeft = 30
    hibernateTick.restart()
    // notify-send with urgency critical gets through Do Not Disturb, quiet
    // while locked and fullscreen; it stays until dismissed.
    Quickshell.execDetached(["notify-send", "-u", "critical", "-t", "30000", "-i", "battery-caution",
      "Battery almost empty", "Hibernating in 30 seconds. Plug in the charger to stay on."])
    announce("Battery " + percent + "%", "Hibernating in 30 s — plug in to stay on")
  }
  function cancelHibernate(why) {
    if (!hibernateTick.running) return
    hibernateTick.stop()
    announce("Hibernate cancelled", why)
  }
  Timer {
    id: hibernateTick
    interval: 1000
    repeat: true
    onTriggered: {
      root.hibernateLeft -= 1
      if (root.hibernateLeft === 10 || root.hibernateLeft === 5)
        root.announce("Battery " + root.percent + "%", "Hibernating in " + root.hibernateLeft + " s")
      if (root.hibernateLeft > 0) return
      stop()
      if (root.hibernateDrill) { root.announce("Hibernate drill", "This is where the laptop would hibernate"); return }
      Quickshell.execDetached(["systemctl", "hibernate"])
    }
  }

  // ── What each mode means ─────────────────────────────────────────
  function applyPersonality() {
    var want = isSaver() ? "saver" : "normal"
    if (want === appliedPersonality) return
    var before = appliedPersonality
    appliedPersonality = want
    if (want === "saver") {
      Quickshell.execDetached(["hyprctl", "eval",
        "hl.config({ decoration = { blur = { enabled = false } }, animations = { enabled = false } })"])
    } else if (before === "saver") {
      // Leaving Saver: put back what the config says (the user may have blur
      // switched off in Quick Settings > Windows) rather than forcing it on.
      Quickshell.execDetached(["hyprctl", "reload"])
    }
    // Normal at startup: nothing to do, the config is already in effect.
    if (isSaver()) applyBrightnessCap()
    else restoreBrightness()
  }

  function applyBrightnessCap() {
    var cap = percent <= (config.criticalAt || 10) ? (config.criticalBrightness || 30) : (config.saverBrightness || 50)
    capProc.cap = cap
    if (!capProc.running) capProc.running = true
  }

  Process {
    id: capProc
    property int cap: 50
    command: ["bash", "-c", "brightnessctl -m -c backlight 2>/dev/null | head -1 | cut -d, -f4 | tr -d %"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var cur = parseInt(String(text || "").trim())
        if (isNaN(cur) || cur <= capProc.cap) return
        if (root.brightnessBeforeCap < 0) root.brightnessBeforeCap = cur
        root.brightnessCappedTo = capProc.cap
        root.saveState()
        Quickshell.execDetached(["brightnessctl", "-q", "-c", "backlight", "set", capProc.cap + "%"])
      }
    }
  }

  function restoreBrightness() {
    if (brightnessBeforeCap < 0) return
    restoreProc.running = true
  }

  Process {
    id: restoreProc
    command: ["bash", "-c", "brightnessctl -m -c backlight 2>/dev/null | head -1 | cut -d, -f4 | tr -d %"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var cur = parseInt(String(text || "").trim())
        // Only undo our own dimming; if the user has moved the slider since, keep their value.
        if (!isNaN(cur) && cur === root.brightnessCappedTo)
          Quickshell.execDetached(["brightnessctl", "-q", "-c", "backlight", "set", root.brightnessBeforeCap + "%"])
        root.brightnessBeforeCap = -1
        root.brightnessCappedTo = -1
        root.saveState()
      }
    }
  }

  // Hyprland reloads (config edits) bring blur/animations back; re-apply.
  Timer {
    interval: 15000
    repeat: true
    running: root.saver
    onTriggered: {
      Quickshell.execDetached(["hyprctl", "eval",
        "hl.config({ decoration = { blur = { enabled = false } }, animations = { enabled = false } })"])
    }
  }

  // ── Awake for media ──────────────────────────────────────────────
  readonly property bool mediaPlaying: {
    var ps = Mpris.players.values
    for (var i = 0; i < ps.length; i++) if (ps[i] && ps[i].isPlaying) return true
    return false
  }
  Nasaq.Fullscreen { id: fullscreen }
  // Omarchy's screensaver is a fullscreen window too; it must not keep itself awake.
  readonly property bool awakeForMedia: Nasaq.Settings.get("power.awakeForMedia", true)
    && (mediaPlaying || (fullscreen.active && fullscreen.windowClass !== "org.omarchy.screensaver"))

  // The inhibitor needs a surface: a 1 px layer with no input and no space.
  // It stays mapped all the time and only the inhibitor comes and goes:
  // Hyprland checks inhibitors when one is created or destroyed, not when a
  // layer maps, so an inhibitor made together with its surface didn't count
  // (fullscreen didn't keep the screen awake), and destroying the surface
  // with it left idle blocked until the next window focus change.
  PanelWindow {
    id: inhibitSurface
    implicitWidth: 1
    implicitHeight: 1
    color: "transparent"
    anchors { top: true; left: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "nasaq-awake"
    mask: Region {}
    IdleInhibitor { window: inhibitSurface; enabled: root.awakeForMedia }
  }

  // ── Game mode ────────────────────────────────────────────────────
  property bool gameMode: false
  property bool gameModeLoaded: false
  readonly property string gameModePath: Quickshell.env("HOME") + "/.local/state/nasaq/gamemode"
  FileView {
    id: gameModeFile
    path: root.gameModePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyGameMode(text().trim() === "1", false)
    onLoadFailed: root.gameModeLoaded = true
  }
  function applyGameMode(on, announceIt) {
    var changed = gameMode !== on || !gameModeLoaded
    var wasLoaded = gameModeLoaded
    gameMode = on
    gameModeLoaded = true
    if (!changed) return
    if (on) applyGameLook()
    else if (wasLoaded) {
      // Put back what the config says, then Saver's own look if it is on.
      Quickshell.execDetached(["hyprctl", "reload"])
      if (isSaver()) { appliedPersonality = ""; applyPersonality() }
    }
    if (announceIt)
      Quickshell.execDetached(["omarchy", "osd", "-i", "󰊴", "-m", Nasaq.Tr.s(on ? "Game mode on" : "Game mode off")])
  }
  function setGameMode(on) {
    if (on === gameMode) return
    Quickshell.execDetached(["bash", "-c", "mkdir -p \"$HOME/.local/state/nasaq\" && printf %s \"$1\" > \"$HOME/.local/state/nasaq/gamemode\"", "nasaq-gamemode", on ? "1" : "0"])
    applyGameMode(on, true)
  }
  function applyGameLook() {
    // Windows only: one runtime rule makes every window opaque, unblurred and
    // shadowless (their transparency comes from window rules, which decoration
    // options do not override). Blur itself stays on, so the desktop widgets and
    // the shell's panels keep their glass. Leaving game mode reloads the
    // config, which drops the rule.
    Quickshell.execDetached(["hyprctl", "eval",
      "hl.config({ animations = { enabled = false }, decoration = { shadow = { enabled = false } } }); " +
      "hl.window_rule({ match = { class = \".*\" }, opaque = true, no_blur = true, no_shadow = true }); " +
      // NASAQ's own windows (Settings) are shell glass like the island: excluded.
      "hl.window_rule({ match = { class = \"^org\\\\.quickshell$\" }, opaque = false, no_blur = false, no_shadow = false })"])
  }
  // A config reload (an edit, the Windows card) brings the effects back; re-apply.
  Connections {
    target: Hyprland
    function onRawEvent(event) { if (root.gameMode && event && event.name === "configreloaded") root.applyGameLook() }
  }

  IpcHandler {
    target: "nasaq.power"
    function status(): string {
      return JSON.stringify({ profile: root.profile, onBattery: root.onBattery, percent: root.percent,
        autoLowPower: root.autoLowPower, personality: root.appliedPersonality,
        awakeForMedia: root.awakeForMedia, mediaPlaying: root.mediaPlaying, fullscreen: fullscreen.active,
        hibernateAt: root.hibernateAt, hibernateEnabled: root.hibernateEnabled, hibernateCountdown: hibernateTick.running ? root.hibernateLeft : -1,
        gameMode: root.gameMode })
    }
    // The countdown as it would run at the threshold, without the hibernate
    // at the end (for trying it on a machine that is not at 3 %).
    function hibernateDrill(): string { root.startHibernateCountdown(true); return "ok" }
    function hibernateCancel(): string { root.cancelHibernate("Cancelled"); return "ok" }
  }

  IpcHandler {
    target: "nasaq.gamemode"
    function toggle(): string { root.setGameMode(!root.gameMode); return root.gameMode ? "on" : "off" }
    function on(): string { root.setGameMode(true); return "on" }
    function off(): string { root.setGameMode(false); return "off" }
    function status(): string { return root.gameMode ? "on" : "off" }
  }
}
