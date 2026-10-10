import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// NASAQ: Apple-style power behaviour on top of power-profiles-daemon.
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
      // the user picked another mode himself — respect it.
      autoLowPower = false
      profileBeforeLow = ""
      saveState()
    }
    applyPersonality()
  }

  onProfileChanged: evaluate()
  onOnBatteryChanged: evaluate()
  onPercentChanged: { evaluate(); if (isSaver()) applyBrightnessCap() }
  onLoadedChanged: evaluate()

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
      // switched off in Control Center > Windows) rather than forcing it on.
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
        // Only undo our own dimming; if the user moved the slider since, keep his.
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

  IpcHandler {
    target: "nasaq.power"
    function status(): string {
      return JSON.stringify({ profile: root.profile, onBattery: root.onBattery, percent: root.percent,
        autoLowPower: root.autoLowPower, personality: root.appliedPersonality })
    }
  }
}
