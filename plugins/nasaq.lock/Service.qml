import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import Quickshell.Services.UPower
import qs.Commons

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"

  property bool lockRequested: false
  property bool pendingSessionLock: false
  property bool authenticatingPassword: false
  property bool fingerprintAuthenticating: false
  property bool passwordPamConfigured: false
  property bool fingerprintConfigured: false
  property bool previewVisible: false
  property string enteredPassword: ""
  property string pendingPassword: ""
  property string failureMessage: ""
  property int failedAttempts: 0
  property string backgroundPath: ""
  property int backgroundVersion: 0
  property string lastEvent: "init"
  property string lastEventAt: ""
  property bool strandedLock: false
  property bool strandedLockResolved: false
  // NASAQ: the lock screen sits on the desktop itself, blurred: a full-size
  // snapshot of each screen, taken just before locking (about 80 ms; scaling
  // it down in grim costs more than it saves), so the lock's first frame
  // already shows it. Kept in the runtime dir and removed on unlock.
  readonly property string captureDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/nasaq-lock"
  property bool capturing: false
  property bool captureForPreview: false
  property int captureVersion: 0
  // Nasaq.Motion's scale, read here because the lock imports no other plugin
  // folder: settings.json motion.scale, and 0 in power saver.
  property real motionSetting: 1
  property bool nowPlayingSetting: true
  readonly property real motionScale: powerProfile === "power-saver" ? 0 : Math.max(0, Math.min(1.5, motionSetting))
  FileView {
    path: (Quickshell.env("HOME") || "") + "/.config/omarchy/nasaq/settings.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var all = JSON.parse(text())
        var m = all.motion
        root.motionSetting = m && m.scale !== undefined ? Number(m.scale) : 1
        root.nowPlayingSetting = !(all.lock && all.lock.nowPlaying === false)
      } catch (e) {}
    }
  }
  // NASAQ: how long the locked screen stays lit after the last input, picked
  // from the slider on the lock screen and kept across locks. -1 = never.
  readonly property int defaultBlankTimeoutMs: 12 * 60 * 60 * 1000
  property int blankTimeoutMs: defaultBlankTimeoutMs
  property double suppressWakeUntil: 0
  // On battery the power mode caps how long the locked display stays lit
  // (Saver 1 min, Balanced 10 min); plugged in, the user's own choice stands.
  property string powerProfile: ""
  readonly property int effectiveBlankMs: {
    if (!UPower.onBattery) return blankTimeoutMs
    var cap = powerProfile === "power-saver" ? 60000 : powerProfile === "balanced" ? 600000 : -1
    if (cap < 0) return blankTimeoutMs
    return blankTimeoutMs < 0 ? cap : Math.min(blankTimeoutMs, cap)
  }
  onEffectiveBlankMsChanged: if (lockRequested) armBlankTimer()

  readonly property bool locked: capturing || lockRequested || sessionLock.locked || sessionLock.secure
  readonly property bool authenticating: authenticatingPassword || fingerprintAuthenticating
  // Published for the notification service, which keeps toasts off a locked
  // screen: ~/.local/state/nasaq/locked holds "1" or "0".
  function publishLocked() {
    Quickshell.execDetached(["bash", "-c", "mkdir -p \"$HOME/.local/state/nasaq\" && printf %s \"$1\" > \"$HOME/.local/state/nasaq/locked\"", "nasaq-lock", locked ? "1" : "0"])
  }
  onLockedChanged: publishLocked()

  function realScreenCount() {
    var screens = Quickshell.screens || []
    var count = 0

    for (var i = 0; i < screens.length; i++) {
      var screen = screens[i]
      if (screen && screen.name && screen.width > 0 && screen.height > 0) count += 1
    }

    return count
  }

  function hasRealScreen() {
    return realScreenCount() > 0
  }

  // Omarchy waits 500 ms for the screens to settle before every lock. That
  // matters on resume or when a monitor is being plugged in, not when the user
  // just pressed the key, so the wait is kept only when the screens changed
  // in the last few seconds.
  property double lastScreensChange: 0
  function queueSessionLock() {
    pendingSessionLock = true
    if (hasRealScreen() && Date.now() - lastScreensChange > 3000 && !sessionLockStabilizeTimer.running) {
      requestSessionLock()
      if (sessionLock.locked) return
    }
    if (!sessionLockStabilizeTimer.running) logEvent("lock-pending: screen-stabilizing")
    sessionLockStabilizeTimer.restart()
    if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
  }

  function requestSessionLock() {
    if (!lockRequested || sessionLock.locked || sessionLock.secure) return
    if (sessionLockStabilizeTimer.running) return

    if (!hasRealScreen()) {
      if (!pendingSessionLock || lastEvent !== "lock-pending: no-real-screen") logEvent("lock-pending: no-real-screen")
      pendingSessionLock = true
      if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
      return
    }

    pendingSessionLock = false
    pendingSessionLockTimer.stop()
    sessionLock.locked = true
  }

  // ext-session-lock outlives its client, and a restart carries no lock over, so
  // a session locked this early is an orphan behind Hyprland's failsafe. Outputs
  // are often still absent here, so ask until the answer means something.
  function checkStrandedLock() {
    if (strandedLockResolved || strandedLockCheckProc.running) return

    // A lock this shell took is nobody's orphan.
    if (locked || lockRequested) {
      strandedLockResolved = true
      return
    }

    strandedLockCheckProc.running = true
  }

  function recoverStrandedLock() {
    if (!strandedLock || locked || !passwordPamConfigured) return

    strandedLock = false
    logEvent("lock-stranded: recovering")
    beginLock()
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function refreshFingerprintStatus() {
    if (!fingerprintCheckProc.running) fingerprintCheckProc.running = true
  }

  function logEvent(event) {
    lastEvent = event
    lastEventAt = new Date().toISOString()
    console.log("omarchy lock " + lastEventAt + " " + event)
  }

  function resetAuthenticationState() {
    enteredPassword = ""
    pendingPassword = ""
    failureMessage = ""
    failedAttempts = 0
    authenticatingPassword = false
    fingerprintAuthenticating = false
    fingerprintRetryTimer.stop()
    if (passwordPam.active) passwordPam.abort()
    if (fingerprintPam.active) fingerprintPam.abort()
  }

  function beginLock() {
    if (!passwordPamConfigured) {
      logEvent("lock-denied: missing-pam")
      return false
    }

    // A real lock always wins over a preview capture still in flight.
    if (capturing) { captureForPreview = false; return true }
    startCapture(false)
    return true
  }

  function startCapture(forPreview) {
    captureForPreview = forPreview
    capturing = true
    captureTimeout.restart()
    captureProc.running = true
  }

  function finishCapture() {
    if (!capturing) return
    capturing = false
    captureTimeout.stop()
    if (captureProc.running) captureProc.running = false
    captureVersion += 1
    if (captureForPreview) {
      refreshBackground()
      previewVisible = true
      return
    }
    lockNow()
  }

  Process {
    id: profileProc
    // D-Bus read, not powerprofilesctl (Python, segfaults on exit now and then).
    command: ["bash", "-c", "busctl get-property net.hadess.PowerProfiles /net/hadess/PowerProfiles net.hadess.PowerProfiles ActiveProfile 2>/dev/null | sed -E 's/^s \"(.*)\"$/\\1/'"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.powerProfile = String(text || "").trim() }
  }

  function lockNow() {
    if (!profileProc.running) profileProc.running = true
    Quickshell.execDetached(["nasaq-sound", "lock"])
    resetAuthenticationState()
    lockRequested = true
    armBlankTimer()
    logEvent("lock-requested")
    queueSessionLock()

    Qt.callLater(function() {
      root.refreshBackground()
      root.refreshFingerprintStatus()
    })

    return true
  }

  // A good password: the lock fades back to the sharp desktop first
  // (LockView.leaving), then unlocks.
  property bool leaving: false
  Timer { id: leaveTimer; interval: Math.round(350 * root.motionScale) + 30; onTriggered: root.finishUnlock() }
  function beginUnlock() {
    if (!root.locked && !lockRequested) return
    if (leaving) return
    if (root.motionScale <= 0) { finishUnlock(); return }
    leaving = true
    leaveTimer.restart()
  }

  function finishUnlock() {
    leaveTimer.stop()
    leaving = false
    if (!root.locked && !lockRequested) return
    Quickshell.execDetached(["nasaq-sound", "unlock"])

    lockRequested = false
    pendingSessionLock = false
    sessionLockStabilizeTimer.stop()
    pendingSessionLockTimer.stop()
    resetAuthenticationState()
    idleBlankTimer.stop()
    sessionLock.locked = false
    logEvent("unlocked")
    runWake()
    clearCaptureProc.running = true
  }

  function armBlankTimer() {
    if (effectiveBlankMs < 0) {
      idleBlankTimer.stop()
      return
    }
    idleBlankTimer.armedAt = Date.now()
    idleBlankTimer.restart()
  }

  function setBlankTimeout(ms) {
    var next = Math.round(Number(ms))
    if (isNaN(next) || next === blankTimeoutMs) return
    blankTimeoutMs = next
    blankTimeoutFile.setText(String(next) + "\n")
    if (lockRequested) armBlankTimer()
  }

  // "Turn Off Display" on the lock screen. The click itself (and the hand
  // settling on the mouse) would wake the panel straight back up, so input is
  // ignored for a moment first.
  function blankNow() {
    if (!lockRequested) return
    suppressWakeUntil = Date.now() + 1500
    idleBlankTimer.stop()
    runBlank()
  }

  function runWake() {
    if (Date.now() < suppressWakeUntil) return
    if (!wakeProcess.running) wakeProcess.running = true
    if (lockRequested) armBlankTimer()
  }

  function runBlank() {
    if (!blankProcess.running) blankProcess.running = true
  }

  function submitPassword(value) {
    var password = String(value || "")
    if (!lockRequested || authenticatingPassword || password.length === 0) return

    runWake()
    pendingPassword = password
    failureMessage = ""
    authenticatingPassword = true

    if (!passwordPam.start()) {
      handlePasswordFailure()
      return
    }

    Qt.callLater(respondToPasswordPrompt)
  }

  function respondToPasswordPrompt() {
    if (!authenticatingPassword || !passwordPam.active || !passwordPam.responseRequired) return
    passwordPam.respond(pendingPassword)
  }

  function handlePasswordFailure() {
    if (!lockRequested) return

    authenticatingPassword = false
    enteredPassword = ""
    pendingPassword = ""
    failedAttempts += 1
    failureMessage = "Authentication failed (" + failedAttempts + ")"
    runWake()
  }

  function startFingerprint() {
    if (!lockRequested || !sessionLock.secure || !fingerprintConfigured) return
    if (fingerprintPam.active || fingerprintAuthenticating) return

    fingerprintAuthenticating = true
    if (!fingerprintPam.start()) {
      fingerprintAuthenticating = false
    }
  }

  function handleFingerprintFinished(result) {
    fingerprintAuthenticating = false

    if (!lockRequested) return
    if (result === PamResult.Success) {
      beginUnlock()
    } else if (fingerprintConfigured) {
      fingerprintRetryTimer.restart()
    }
  }

  WlSessionLock {
    id: sessionLock

    locked: false

    onSecureStateChanged: {
      root.logEvent("secure=" + secure)
      if (secure) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.startFingerprint()
      }
    }

    onLockStateChanged: {
      root.logEvent("session-locked=" + locked)

      if (locked) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
      }

      if (!locked && root.lockRequested) {
        root.lockRequested = false
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.resetAuthenticationState()
        root.runWake()
      }
    }

    WlSessionLockSurface {
      id: lockSurface
      color: Color.background

      LockView {
        id: lockView
        anchors.fill: parent
        backgroundPath: root.backgroundPath
        backgroundVersion: root.backgroundVersion
        // Empty until the surface knows its screen: a path without the name
        // would load (and fail) at once, since the load is synchronous.
        capturePath: lockSurface.screen ? root.captureDir + "/" + lockSurface.screen.name + ".ppm" : ""
        motionScale: root.motionScale
        showNowPlaying: root.nowPlayingSetting
        leaving: root.leaving
        surfaceShown: sessionLock.secure
        captureVersion: root.captureVersion
        fingerprintConfigured: root.fingerprintConfigured
        screenName: lockSurface.screen ? lockSurface.screen.name : ""
        authenticatingPassword: root.authenticatingPassword
        failureMessage: root.failureMessage
        failedAttempts: root.failedAttempts
        inputEnabled: root.lockRequested
        loadBackground: root.locked
        passwordText: root.enteredPassword
        onPasswordTextEdited: function(password) { root.enteredPassword = password }
        onSubmitPassword: function(password) { root.submitPassword(password) }
        onClearFailureRequested: root.failureMessage = ""
        onWakeRequested: root.runWake()
        blankTimeoutMs: root.blankTimeoutMs
        onBlankTimeoutPicked: function(ms) { root.setBlankTimeout(ms) }
        onBlankNowRequested: root.blankNow()
      }

    }
  }

  PanelWindow {
    id: previewWindow
    visible: root.previewVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-lock-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    LockView {
      anchors.fill: parent
      backgroundPath: root.backgroundPath
      backgroundVersion: root.backgroundVersion
      capturePath: previewWindow.screen ? root.captureDir + "/" + previewWindow.screen.name + ".ppm" : ""
      motionScale: root.motionScale
      showNowPlaying: root.nowPlayingSetting
      blankTimeoutMs: root.blankTimeoutMs
      captureVersion: root.captureVersion
      fingerprintConfigured: root.fingerprintConfigured
      screenName: previewWindow.screen ? previewWindow.screen.name : ""
      authenticatingPassword: false
      failureMessage: ""
      failedAttempts: 0
      inputEnabled: false
      loadBackground: root.previewVisible
      passwordText: ""
    }

    MouseArea {
      anchors.fill: parent
      z: -1
      acceptedButtons: Qt.RightButton
      onClicked: root.previewVisible = false
    }

    Item {
      focus: root.previewVisible
      Keys.onEscapePressed: root.previewVisible = false
    }
  }

  PamContext {
    id: passwordPam
    config: "omarchy-lock-password"
    user: root.userName

    onResponseRequiredChanged: root.respondToPasswordPrompt()
    onPamMessage: root.respondToPasswordPrompt()

    onCompleted: function(result) {
      root.authenticatingPassword = false
      root.pendingPassword = ""

      if (!root.lockRequested) return
      if (result === PamResult.Success) root.beginUnlock()
      else root.handlePasswordFailure()
    }

    onError: function(error) {
      root.handlePasswordFailure()
    }
  }

  PamContext {
    id: fingerprintPam
    config: "omarchy-lock-fingerprint"
    user: root.userName

    onCompleted: function(result) {
      root.handleFingerprintFinished(result)
    }

    onError: function(error) {
      root.fingerprintAuthenticating = false
      if (root.lockRequested && root.fingerprintConfigured) fingerprintRetryTimer.restart()
    }
  }

  Timer {
    id: fingerprintRetryTimer
    interval: 250
    repeat: false
    onTriggered: root.startFingerprint()
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = String(text || "").trim()
        if (next !== root.backgroundPath) {
          root.backgroundPath = next
          root.backgroundVersion += 1
        }
      }
    }
  }

  Process {
    id: fingerprintCheckProc
    command: ["bash", "-c", "if [[ -f /etc/pam.d/omarchy-lock-fingerprint ]] && command -v fprintd-list >/dev/null 2>&1 && fprintd-list \"$USER\" 2>/dev/null | grep -qi finger; then echo yes; else echo no; fi"]
    stdout: StdioCollector { id: fingerprintCheckStdout; waitForEnd: true }
    onExited: {
      root.fingerprintConfigured = String(fingerprintCheckStdout.text || "").trim() === "yes"
      if (root.lockRequested && root.fingerprintConfigured) root.startFingerprint()
      else if (!root.fingerprintConfigured && fingerprintPam.active) fingerprintPam.abort()
    }
  }

  Process {
    id: strandedLockCheckProc
    command: ["bash", "-c", "omarchy-hyprland-session-locked"]
    onExited: function(exitCode) {
      // No output to read the lock off yet.
      if (exitCode === 2) return

      root.strandedLockResolved = true

      // A lock taken while this was in flight is this shell's own.
      root.strandedLock = exitCode === 0 && !root.locked && !root.lockRequested
      root.recoverStrandedLock()
    }
  }

  // The screensaver is closed first so the snapshot shows the real windows.
  // PPM: no compression, the fastest to write and to load.
  Process {
    id: captureProc
    command: ["bash", "-c",
      "dir=\"$1\"; mkdir -p -m 700 \"$dir\"; rm -f \"$dir\"/*.ppm \"$dir\"/*.jpg; " +
      "if pgrep -x ttfx >/dev/null || pgrep -f '[o]rg.omarchy.screensaver' >/dev/null; then " +
      "pkill -x ttfx; pkill -f '[o]rg.omarchy.screensaver'; sleep 0.35; fi; " +
      "for m in $(hyprctl monitors -j | jq -r '.[].name'); do " +
      "grim -o \"$m\" -t ppm \"$dir/$m.ppm\" & done; wait",
      "nasaq-lock-capture", root.captureDir]
    onExited: root.finishCapture()
  }

  Process {
    id: clearCaptureProc
    command: ["bash", "-c", "rm -f \"$1\"/*.ppm", "nasaq-lock-clear", root.captureDir]
  }

  Timer {
    id: captureTimeout
    interval: 2000
    repeat: false
    onTriggered: { root.logEvent("capture-timeout"); root.finishCapture() }
  }

  Process {
    id: wakeProcess
    command: ["bash", "-c", "omarchy-system-wake"]
  }

  Process {
    id: blankProcess
    command: ["bash", "-c", "omarchy-brightness-keyboard off; omarchy-brightness-display off"]
  }

  Timer {
    id: idleBlankTimer
    interval: Math.max(1000, root.effectiveBlankMs)
    repeat: false
    property double armedAt: 0
    onTriggered: {
      // A countdown frozen by suspend fires right after resume, which would
      // blank the freshly woken unlock screen under the user. Wall-clock time
      // exposes the gap: take a fresh run-up instead of blanking.
      if (Date.now() - armedAt > interval + 2000) {
        root.armBlankTimer()
        return
      }
      // Only a password check in flight should hold the display up. The
      // fingerprint PAM stays armed for the whole lock, so gating on
      // `authenticating` here would keep the panel lit until unlock.
      if (root.lockRequested && !root.authenticatingPassword) root.runBlank()
    }
  }

  Timer {
    id: sessionLockStabilizeTimer
    interval: 500
    repeat: false
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: pendingSessionLockTimer
    interval: 100
    repeat: true
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: strandedLockRetryTimer
    interval: 500
    repeat: true
    // Covers the compositor settling; screens coming back re-arm it.
    readonly property int budget: 20
    property int remaining: 20
    running: !root.strandedLockResolved && remaining > 0

    function rearm() {
      if (!root.strandedLockResolved) remaining = budget
    }

    onTriggered: {
      remaining -= 1
      root.checkStrandedLock()
    }
  }

  Connections {
    target: Quickshell
    function onScreensChanged() {
      root.lastScreensChange = Date.now()
      root.requestSessionLock()

      // A monitor still coming up has no workspace, so cannot answer yet.
      strandedLockRetryTimer.rearm()
      root.checkStrandedLock()
    }
  }

  onAuthenticatingPasswordChanged: {
    if (!lockRequested) return
    if (authenticatingPassword) idleBlankTimer.stop()
    else armBlankTimer()
  }

  FileView {
    id: blankTimeoutFile
    path: root.stateHome + "/nasaq/lock-blank-timeout"
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var v = parseInt(String(text() || "").trim())
      if (!isNaN(v)) root.blankTimeoutMs = v
    }
  }

  FileView {
    path: "/etc/pam.d/omarchy-lock-password"
    watchChanges: true
    printErrors: false
    onLoaded: root.passwordPamConfigured = true
    onLoadFailed: root.passwordPamConfigured = false
    onFileChanged: reload()
  }

  // No lock before PAM is known good. An answer from before then may be stale --
  // the failsafe can be cleared from a TTY -- so re-ask rather than act on it.
  onPasswordPamConfiguredChanged: {
    if (!passwordPamConfigured) return

    strandedLock = false
    strandedLockResolved = false
    strandedLockRetryTimer.rearm()
    checkStrandedLock()
  }

  Component.onCompleted: {
    publishLocked()
    refreshBackground()
    refreshFingerprintStatus()
    checkStrandedLock()
  }

  IpcHandler {
    target: "lock"

    function lock(): string {
      if (!root.passwordPamConfigured) return "missing-pam"
      if (!root.locked && !root.beginLock()) return "failed"
      return "ok"
    }

    function isLocked(): string {
      return root.locked ? "true" : "false"
    }

    function status(): string {
      return JSON.stringify({
        locked: root.locked,
        requested: root.lockRequested,
        pending: root.pendingSessionLock,
        sessionLocked: sessionLock.locked,
        secure: sessionLock.secure,
        realScreens: root.realScreenCount(),
        passwordPam: root.passwordPamConfigured,
        fingerprint: root.fingerprintConfigured,
        authenticating: root.authenticating,
        lastEvent: root.lastEvent,
        lastEventAt: root.lastEventAt
      })
    }

    function preview(): string {
      root.refreshFingerprintStatus()
      if (!root.capturing && !root.locked) root.startCapture(true)
      return "ok"
    }

    function hidePreview(): string {
      root.previewVisible = false
      return "ok"
    }
  }
}
