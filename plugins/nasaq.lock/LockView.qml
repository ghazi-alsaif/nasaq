import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui

// NASAQ: lock screen. The open windows (captured by the shell itself as the
// lock comes up) blur in behind a large clock, the password pill sits low and
// centred, and a control-center popover hangs off the top-right status icons.
Item {
  id: root

  property string backgroundPath: ""
  property int backgroundVersion: 0
  // The screen to capture. Shown sharp first, then blurred over Motion.slow.
  property var captureScreen: null
  property int captureVersion: 0
  // Same scale as Nasaq.Motion (1 normal, 0.5 reduced, 0 off); passed in
  // because the lock doesn't import other plugin folders.
  property real motionScale: 1
  property bool showNowPlaying: true
  // The player to show: the one playing, else the first that has a track.
  readonly property var player: {
    var list = Mpris.players ? Mpris.players.values : []
    var paused = null
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      if (!p || !p.trackTitle) continue
      if (p.isPlaying) return p
      if (!paused) paused = p
    }
    return paused
  }
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  property bool syncingPasswordText: false
  property bool useCapture: true
  property real reveal: 0
  NumberAnimation on reveal {
    id: revealAnim
    running: false
    to: 1
    duration: Math.round(600 * root.motionScale)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: [0.23, 1.00, 0.32, 1.00, 1, 1]
  }
  function startReveal() {
    if (root.motionScale <= 0) { revealAnim.stop(); reveal = 1; return }
    revealAnim.restart()
  }
  property bool controlsOpen: false
  property bool displayOpen: false
  property int blankTimeoutMs: 12 * 60 * 60 * 1000

  // Slider stops for "turn the display off after"; -1 = never.
  readonly property var blankStops: [5000, 15000, 30000, 60000, 120000, 300000, 600000, 900000,
    1800000, 3600000, 7200000, 10800000, 21600000, 43200000, -1]
  readonly property var blankLabels: ["5 sec", "15 sec", "30 sec", "1 min", "2 min", "5 min", "10 min", "15 min",
    "30 min", "1 hour", "2 hours", "3 hours", "6 hours", "12 hours", "Never"]
  readonly property int blankIndex: {
    if (blankTimeoutMs < 0) return blankStops.length - 1
    var best = 0
    for (var i = 0; i < blankStops.length - 1; i++)
      if (Math.abs(blankStops[i] - blankTimeoutMs) < Math.abs(blankStops[best] - blankTimeoutMs)) best = i
    return best
  }

  readonly property string textFont: "IBM Plex Sans Arabic"
  readonly property string monoFont: "JetBrains Mono"

  // Colours follow the active Omarchy theme, mapped exactly like the NASAQ
  // login screen (login/nasaq-login/Main.qml), so the two look like one.
  // Color.* is live, so a theme change repaints the lock while it is up.
  readonly property color fg: Color.foreground       // text, icons and the glass tint
  readonly property color accent: Color.accent       // avatar, cursor, selection, Matrix rain
  readonly property color surface: Color.background  // base under the wallpaper, dark panels
  readonly property color urgent: Color.urgent       // wrong password, armed power button
  function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  readonly property string iconFont: Style.font.family
  // Shown name, the same rule on the lock, login and boot screens: the
  // account's full name (first GECOS field in /etc/passwd) if set, else the
  // user name exactly as it is.
  readonly property string loginName: Quickshell.env("USER") || ""
  property string fullName: ""
  FileView {
    path: "/etc/passwd"
    printErrors: false
    onLoaded: {
      var lines = String(text()).split("\n")
      for (var i = 0; i < lines.length; i++) {
        var f = lines[i].split(":")
        if (f[0] === root.loginName && f.length > 4) { root.fullName = f[4].split(",")[0].trim(); return }
      }
    }
  }
  readonly property string userName: fullName.length > 0 ? fullName : loginName
  readonly property string avatarPath: (Quickshell.env("HOME") || "") + "/.face"
  readonly property bool errorState: failureMessage.length > 0
  readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && !errorState

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()
  signal blankTimeoutPicked(int ms)
  signal blankNowRequested()

  function fileUrl(path, version) {
    if (!path) return ""
    var encoded = String(path).split("/").map(encodeURIComponent).join("/")
    return "file://" + encoded + "?v=" + version
  }

  function forcePasswordFocus() {
    // Leave the keyboard alone while a Wi-Fi password is being typed.
    if (controls.keyboardBusy && controlsOpen) return
    passwordInput.forceActiveFocus()
  }

  function syncPasswordText() {
    if (passwordInput.text === passwordText) return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }

  onPasswordTextChanged: syncPasswordText()
  onCaptureVersionChanged: recapture()
  function recapture() {
    useCapture = true
    reveal = 0
    if (shot.captureSource) shot.captureFrame()
    captureFallback.restart()
  }
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }
  onLoadBackgroundChanged: {
    if (!loadBackground) { controlsOpen = false; displayOpen = false; reveal = 0; return }
    recapture()
  }
  onFailedAttemptsChanged: if (failedAttempts > 0) shake.restart()
  Component.onCompleted: {
    if (loadBackground) recapture()
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }

  Rectangle {
    anchors.fill: parent
    color: Color.background

    // In-shell capture: Quickshell copies this screen as the lock surface
    // appears, before the lock covers it. No external grab, so the lock comes
    // up at once.
    ScreencopyView {
      id: shot
      anchors.fill: parent
      captureSource: root.loadBackground ? root.captureScreen : null
      live: false
      visible: false
      onHasContentChanged: if (hasContent && root.useCapture) { captureFallback.stop(); root.startReveal() }
    }

    // No capture within a second (none allowed, or no screen): the wallpaper.
    Timer {
      id: captureFallback
      interval: 1000
      onTriggered: if (!shot.hasContent) { root.useCapture = false; root.startReveal() }
    }

    Image {
      id: wallpaper
      anchors.fill: parent
      source: !root.loadBackground || root.useCapture ? "" : root.fileUrl(root.backgroundPath, root.backgroundVersion)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      visible: false
    }

    readonly property bool backdropReady: root.useCapture ? shot.hasContent : wallpaper.status === Image.Ready

    MultiEffect {
      anchors.fill: parent
      source: root.useCapture ? shot : wallpaper
      autoPaddingEnabled: false
      blurEnabled: true
      // The desktop shows sharp for a moment and blurs in (Motion.slow).
      blur: 0.5 * root.reveal
      blurMax: 64
      blurMultiplier: 1.0
      // Blur only — no colour or brightness shift (design choice, 2026-10-06).
      visible: root.loadBackground && parent.backdropReady
    }

    // Soft vertical gradient: a touch darker at the top and bottom so the
    // clock and the power row read on any backdrop.
    Rectangle {
      anchors.fill: parent
      visible: false   // gradient off: the backdrop is blurred only
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.28) }
        GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.04) }
        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.38) }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.controlsOpen = false; root.displayOpen = false; controls.promptSsid = ""; root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: root.wakeRequested()
    }

    // ── Date and clock ───────────────────────────────────────────────
    Column {
      id: clockColumn
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: Math.round(root.height * 0.17)
      spacing: -Math.round(root.height * 0.006)

      property date now: new Date()
      Timer {
        interval: 1000
        running: root.loadBackground
        repeat: true
        triggeredOnStart: true
        onTriggered: clockColumn.now = new Date()
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.locale("en_US").toString(clockColumn.now, "dddd, MMMM d")
        color: root.tint(root.fg, 0.9)
        font.family: root.monoFont
        font.weight: Font.Medium
        font.pixelSize: Math.round(root.height * 0.026)
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.locale("en_US").toString(clockColumn.now, "h:mm AP").replace(/\s*[AP]M$/i, "")
        color: root.tint(root.fg, 0.95)
        font.family: root.monoFont
        font.weight: Font.Normal
        font.pixelSize: Math.round(root.height * 0.13)
      }
    }

    // ── Matrix rain between the clock and the login ──────────────────
    MatrixRain {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: loginColumn.bottom
      anchors.topMargin: 10
      anchors.bottom: nowPlaying.visible ? nowPlaying.top : powerRow.top
      anchors.bottomMargin: 10
      width: Math.min(620, Math.round(root.width * 0.42))
      running: root.loadBackground
      opacity: 0.85
      color: root.accent
      headColor: Qt.lighter(root.accent, 1.6)
    }

    // ── Top-right status cluster (opens the control center) ──────────
    Rectangle {
      id: statusButton
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 14
      height: 34
      width: statusRow.implicitWidth + 24
      radius: height / 2
      color: root.controlsOpen ? root.tint(root.fg, 0.28)
           : (statusMouse.containsMouse ? root.tint(root.fg, 0.18) : root.tint(root.fg, 0.10))
      Behavior on color { ColorAnimation { duration: 120 } }

      Row {
        id: statusRow
        anchors.centerIn: parent
        spacing: 14

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: controls.layoutShort
          visible: text.length > 0
          color: root.fg
          font.family: root.textFont
          font.weight: Font.DemiBold
          font.pixelSize: 13
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: controls.wifiIcon
          color: root.fg
          font.family: root.iconFont
          font.pixelSize: 16
        }
        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: 4
          visible: controls.batteryPercent >= 0
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: controls.batteryPercent + "%"
            color: root.fg
            font.family: root.textFont
            font.pixelSize: 13
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: controls.batteryIcon
            color: root.fg
            font.family: root.iconFont
            font.pixelSize: 16
          }
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰔡"
          color: root.fg
          font.family: root.iconFont
          font.pixelSize: 16
        }
      }

      MouseArea {
        id: statusMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          root.wakeRequested()
          root.controlsOpen = !root.controlsOpen
          root.displayOpen = false
          root.forcePasswordFocus()
        }
      }
    }

    ControlCenter {
      id: controls
      anchors.top: statusButton.bottom
      anchors.right: statusButton.right
      anchors.topMargin: 8
      textFont: root.textFont
      iconFont: root.iconFont
      active: root.loadBackground
      interactive: root.inputEnabled
      opened: root.controlsOpen
      onInteracted: { root.wakeRequested(); root.forcePasswordFocus() }
    }

    // ── Display sleep: corner button + card ──────────────────────────
    Rectangle {
      id: displayButton
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: 22
      width: 38
      height: 38
      radius: 19
      color: root.tint(root.fg, root.displayOpen ? 0.26 : (displayMouse.containsMouse ? 0.18 : 0.08))
      opacity: root.displayOpen || displayMouse.containsMouse ? 1 : 0.6
      Behavior on color { ColorAnimation { duration: 120 } }
      Behavior on opacity { NumberAnimation { duration: 160 } }

      Text {
        anchors.centerIn: parent
        text: "󰤄"
        color: root.fg
        font.family: root.iconFont
        font.pixelSize: 17
      }
      MouseArea {
        id: displayMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          root.wakeRequested()
          root.displayOpen = !root.displayOpen
          root.controlsOpen = false
          root.forcePasswordFocus()
        }
      }
    }

    Rectangle {
      id: displayCard
      anchors.right: displayButton.right
      anchors.bottom: displayButton.top
      anchors.bottomMargin: 10
      width: 290
      height: displayCol.implicitHeight + 28
      radius: 18
      color: root.tint(root.surface, 0.66)
      border.color: root.tint(root.fg, 0.14)
      border.width: 1
      transformOrigin: Item.BottomRight
      opacity: root.displayOpen ? 1 : 0
      scale: root.displayOpen ? 1 : 0.94
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

      MouseArea { anchors.fill: parent; onClicked: root.wakeRequested() }

      Column {
        id: displayCol
        x: 14
        y: 14
        width: parent.width - 28
        spacing: 12

        Item {
          width: parent.width
          height: 20
          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Turn display off after"
            color: root.tint(root.fg, 0.75)
            font.family: root.textFont
            font.pixelSize: 13
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.blankLabels[sleepSlider.index]
            color: root.fg
            font.family: root.textFont
            font.weight: Font.DemiBold
            font.pixelSize: 13
          }
        }

        // Notched slider, one notch per stop.
        Item {
          id: sleepSlider
          width: parent.width
          height: 22
          property int index: root.blankIndex
          readonly property int count: root.blankStops.length
          readonly property real step: width / (count - 1)
          Connections {
            target: root
            function onBlankIndexChanged() { if (!sleepMouse.pressed) sleepSlider.index = root.blankIndex }
          }

          Rectangle {
            id: sleepTrack
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4
            radius: 2
            color: root.tint(root.fg, 0.18)
          }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: sleepSlider.index * sleepSlider.step
            height: 4
            radius: 2
            color: root.tint(root.fg, 0.9)
          }
          Repeater {
            model: sleepSlider.count
            delegate: Rectangle {
              required property int index
              x: index * sleepSlider.step - width / 2
              anchors.verticalCenter: parent.verticalCenter
              width: 3
              height: 3
              radius: 1.5
              color: index <= sleepSlider.index ? Util.alpha(Color.background, 0.6) : Util.alpha(Color.foreground, 0.35)
            }
          }
          Rectangle {
            x: sleepSlider.index * sleepSlider.step - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            height: 18
            radius: 9
            color: root.fg
            border.color: Qt.rgba(0, 0, 0, 0.15)
            Behavior on x { enabled: !sleepMouse.pressed; NumberAnimation { duration: 120 } }
          }
          MouseArea {
            id: sleepMouse
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            function pick(x) {
              var i = Math.round((x - 6) / sleepSlider.step)
              sleepSlider.index = Math.max(0, Math.min(sleepSlider.count - 1, i))
              root.wakeRequested()
            }
            onPressed: function(e) { pick(e.x) }
            onPositionChanged: function(e) { if (pressed) pick(e.x) }
            onReleased: root.blankTimeoutPicked(root.blankStops[sleepSlider.index])
          }
        }

        Item {
          width: parent.width
          height: 12
          Text {
            anchors.left: parent.left
            text: "5 sec"
            color: root.tint(root.fg, 0.45)
            font.family: root.textFont
            font.pixelSize: 10
          }
          Text {
            anchors.right: parent.right
            text: "Never"
            color: root.tint(root.fg, 0.45)
            font.family: root.textFont
            font.pixelSize: 10
          }
        }

        Rectangle {
          width: parent.width
          height: 34
          radius: 10
          color: root.tint(root.fg, offMouse.containsMouse ? 0.2 : 0.12)
          Behavior on color { ColorAnimation { duration: 120 } }
          Row {
            anchors.centerIn: parent
            spacing: 8
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "󰶐"
              color: root.fg
              font.family: root.iconFont
              font.pixelSize: 15
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Turn off display now"
              color: root.fg
              font.family: root.textFont
              font.weight: Font.DemiBold
              font.pixelSize: 13
            }
          }
          MouseArea {
            id: offMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.displayOpen = false
              root.blankNowRequested()
            }
          }
        }
      }
    }

    // ── Now playing (above the power row) ────────────────────────────
    // Cover, title and artist, with previous / play-pause / next, so music
    // can be paused or skipped without unlocking.
    Rectangle {
      id: nowPlaying
      readonly property var p: root.player
      visible: root.showNowPlaying && root.loadBackground && !!p
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: powerRow.top
      anchors.bottomMargin: Math.round(root.height * 0.04)
      width: 380
      height: 68
      radius: 18
      color: root.tint(root.fg, 0.14)
      border.color: root.tint(root.fg, 0.22)
      border.width: 1

      Rectangle {
        id: npArt
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 48
        height: 48
        radius: 10
        color: root.tint(root.fg, 0.12)
        clip: true
        Image {
          id: npImage
          anchors.fill: parent
          source: nowPlaying.p && nowPlaying.p.trackArtUrl ? nowPlaying.p.trackArtUrl : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          visible: false
        }
        Rectangle { id: npMask; anchors.fill: parent; radius: 10; visible: false; layer.enabled: true }
        MultiEffect {
          anchors.fill: npImage
          source: npImage
          maskEnabled: true
          maskSource: npMask
          visible: npImage.status === Image.Ready
        }
        Text {
          anchors.centerIn: parent
          visible: npImage.status !== Image.Ready
          text: "󰎆"
          color: root.tint(root.fg, 0.7)
          font.family: root.iconFont
          font.pixelSize: 22
        }
      }

      Column {
        anchors.left: npArt.right
        anchors.leftMargin: 12
        anchors.right: npControls.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
          width: parent.width
          text: nowPlaying.p ? nowPlaying.p.trackTitle : ""
          color: root.fg
          elide: Text.ElideRight
          font.family: root.textFont
          font.weight: Font.DemiBold
          font.pixelSize: 14
        }
        Text {
          width: parent.width
          text: nowPlaying.p ? (nowPlaying.p.trackArtist || nowPlaying.p.identity || "") : ""
          visible: text.length > 0
          color: root.tint(root.fg, 0.7)
          elide: Text.ElideRight
          font.family: root.textFont
          font.pixelSize: 12
        }
      }

      Row {
        id: npControls
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14
        Repeater {
          model: [
            { key: "prev", icon: "󰒮" },
            { key: "play", icon: "" },
            { key: "next", icon: "󰒭" }
          ]
          delegate: Text {
            required property var modelData
            readonly property var pl: nowPlaying.p
            readonly property bool can: !pl ? false
              : modelData.key === "prev" ? pl.canGoPrevious
              : modelData.key === "next" ? pl.canGoNext
              : pl.canTogglePlaying
            text: modelData.key === "play" ? (pl && pl.isPlaying ? "󰏤" : "󰐊") : modelData.icon
            color: root.fg
            opacity: !can ? 0.3 : npMouse.containsMouse ? 1 : 0.82
            scale: npMouse.containsMouse && can ? 1.12 : 1
            font.family: root.iconFont
            font.pixelSize: modelData.key === "play" ? 26 : 20
            anchors.verticalCenter: parent.verticalCenter
            Behavior on scale { NumberAnimation { duration: 120 } }
            MouseArea {
              id: npMouse
              anchors.fill: parent
              anchors.margins: -6
              hoverEnabled: true
              enabled: root.inputEnabled && parent.can
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.wakeRequested()
                var pl = parent.pl
                if (modelData.key === "prev") pl.previous()
                else if (modelData.key === "next") pl.next()
                else pl.togglePlaying()
                Qt.callLater(root.forcePasswordFocus)
              }
            }
          }
        }
      }
    }

    // ── Power row (bottom centre): shut down, restart, sleep ─────────
    // Shut down and restart need a second click within 3 s.
    Column {
      id: powerRow
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Math.round(root.height * 0.08)
      spacing: 8
      property string armed: ""
      Timer { id: powerDisarm; interval: 3000; onTriggered: powerRow.armed = "" }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 34
        Repeater {
          model: [
            { key: "off", icon: "󰐥", label: "Shut down", cmd: "omarchy-system-shutdown", confirm: true },
            { key: "restart", icon: "󰜉", label: "Restart", cmd: "omarchy-system-reboot", confirm: true },
            { key: "sleep", icon: "󰽥", label: "Sleep", cmd: "systemctl suspend", confirm: false }
          ]
          delegate: Text {
            required property var modelData
            text: modelData.icon
            color: powerRow.armed === modelData.key ? Color.urgent : Color.foreground
            opacity: pMouse.containsMouse || powerRow.armed === modelData.key ? 1 : 0.82
            scale: pMouse.containsMouse ? 1.12 : 1
            font.family: root.iconFont
            font.pixelSize: 34
            Behavior on scale { NumberAnimation { duration: 120 } }
            MouseArea {
              id: pMouse
              anchors.fill: parent
              anchors.margins: -8
              hoverEnabled: true
              enabled: root.inputEnabled
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.wakeRequested()
                if (modelData.confirm && powerRow.armed !== modelData.key) {
                  powerRow.armed = modelData.key
                  powerDisarm.restart()
                  return
                }
                powerRow.armed = ""
                Quickshell.execDetached(["bash", "-c", modelData.cmd])
              }
            }
          }
        }
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        height: 14
        text: powerRow.armed === "off" ? "Click again to shut down" : powerRow.armed === "restart" ? "Click again to restart" : ""
        color: root.tint(root.fg, 0.8)
        font.family: root.monoFont
        font.pixelSize: 11
      }
    }

    // ── User and password ────────────────────────────────────────────
    Column {
      id: loginColumn
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: clockColumn.bottom
      anchors.topMargin: Math.round(root.height * 0.05)
      spacing: 12

      // Name pill (icon + user name), like the password pill below it.
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 190
        height: 34
        radius: 17
        color: root.tint(root.fg, 0.20)
        border.color: root.tint(root.fg, 0.22)
        border.width: 1
        Row {
          anchors.centerIn: parent
          spacing: 7
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            height: 18
            radius: 9
            color: root.accent
            Text {
              anchors.centerIn: parent
              text: root.userName.charAt(0).toUpperCase()
              color: root.surface
              font.family: root.monoFont
              font.weight: Font.Bold
              font.pixelSize: 11
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.userName
            color: root.fg
            font.family: root.monoFont
            font.weight: Font.Bold
            font.pixelSize: 14
          }
        }
      }

      Rectangle {
        id: avatar
        visible: false
        anchors.horizontalCenter: parent.horizontalCenter
        width: 64
        height: 64
        radius: 32
        color: root.tint(root.fg, 0.22)
        border.color: root.tint(root.fg, 0.35)
        border.width: 1

        Image {
          id: avatarImage
          anchors.fill: parent
          anchors.margins: 1
          // The circle is hidden in this design (the name pill replaced it), so
          // don't ask for ~/.face at all: it logged "Cannot open" on every load.
          source: parent.visible ? root.fileUrl(root.avatarPath, 0) : ""
          fillMode: Image.PreserveAspectCrop
          visible: false
          asynchronous: true
        }
        Rectangle {
          id: avatarMask
          anchors.fill: avatarImage
          radius: width / 2
          visible: false
          layer.enabled: true
        }
        MultiEffect {
          anchors.fill: avatarImage
          source: avatarImage
          maskEnabled: true
          maskSource: avatarMask
          visible: avatarImage.status === Image.Ready
        }
        Text {
          anchors.centerIn: parent
          visible: avatarImage.status !== Image.Ready
          text: root.userName.charAt(0).toUpperCase()
          color: root.fg
          font.family: root.textFont
          font.weight: Font.DemiBold
          font.pixelSize: 28
        }
      }

      Item {
        id: fieldHolder
        anchors.horizontalCenter: parent.horizontalCenter
        width: 190
        height: 34

        Rectangle {
          id: field
          width: parent.width
          height: parent.height
          radius: height / 2
          color: root.tint(root.fg, passwordInput.activeFocus ? 0.26 : 0.20)
          border.width: 1
          border.color: root.errorState ? root.tint(root.urgent, 0.8) : root.tint(root.fg, 0.22)

          TextInput {
            id: passwordInput
            anchors.fill: parent
            anchors.leftMargin: 34
            anchors.rightMargin: 34
            verticalAlignment: TextInput.AlignVCenter
            horizontalAlignment: TextInput.AlignHCenter
            activeFocusOnPress: true
            clip: true
            enabled: root.inputEnabled && !root.authenticatingPassword
            readOnly: root.authenticatingPassword
            echoMode: TextInput.Password
            passwordCharacter: "●"
            passwordMaskDelay: 0
            color: root.fg
            selectionColor: root.tint(root.accent, 0.45)
            selectedTextColor: root.fg
            font.family: root.textFont
            font.pixelSize: text.length > 0 ? 11 : 13
            font.letterSpacing: text.length > 0 ? 2 : 0
            cursorVisible: activeFocus && root.showPasswordCursor
            cursorDelegate: Rectangle {
              width: 2
              color: Color.accent
              visible: passwordInput.cursorVisible
            }

            onTextChanged: {
              if (!root.syncingPasswordText) root.passwordTextEdited(text)
              if (text.length > 0) root.wakeRequested()
              if (text.length > 0 && root.failureMessage.length > 0) root.clearFailureRequested()
            }

            onAccepted: {
              var submitted = root.passwordText
              root.passwordTextEdited("")
              if (submitted.length > 0) root.submitPassword(submitted)
            }

            Keys.onPressed: function(event) {
              root.wakeRequested()
              if (event.key === Qt.Key_Escape) {
                if (root.controlsOpen || root.displayOpen) { root.controlsOpen = false; root.displayOpen = false }
                else root.passwordTextEdited("")
                event.accepted = true
              } else if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U) {
                root.passwordTextEdited("")
                event.accepted = true
              }
            }
          }

          Text {
            anchors.fill: passwordInput
            textFormat: Text.PlainText
            text: root.authenticatingPassword ? "Checking…" : "Password"
            visible: passwordInput.text.length === 0
            color: root.tint(root.fg, 0.85)
            font.family: root.monoFont
            font.weight: Font.Bold
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }

          // Submit arrow, or a fingerprint hint while the field is empty.
          Rectangle {
            id: submitButton
            anchors.right: parent.right
            anchors.rightMargin: 5
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24
            radius: 12
            visible: passwordInput.text.length > 0 || root.fingerprintConfigured
            color: passwordInput.text.length > 0 ? root.tint(root.fg, submitMouse.containsMouse ? 0.45 : 0.32) : "transparent"

            Text {
              anchors.centerIn: parent
              text: passwordInput.text.length > 0 ? "󰁔" : "󰈷"
              color: root.fg
              font.family: root.iconFont
              font.pixelSize: 15
            }
            MouseArea {
              id: submitMouse
              anchors.fill: parent
              hoverEnabled: true
              enabled: passwordInput.text.length > 0
              cursorShape: Qt.PointingHandCursor
              onClicked: passwordInput.accepted()
            }
          }
        }

        SequentialAnimation {
          id: shake
          loops: 1
          NumberAnimation { target: field; property: "x"; to: -12; duration: 50 }
          NumberAnimation { target: field; property: "x"; to: 12; duration: 70 }
          NumberAnimation { target: field; property: "x"; to: -8; duration: 70 }
          NumberAnimation { target: field; property: "x"; to: 8; duration: 70 }
          NumberAnimation { target: field; property: "x"; to: 0; duration: 50 }
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        height: 16
        text: root.errorState ? "Incorrect password, try again"
            : (root.fingerprintConfigured ? "Touch the sensor or enter password" : "")
        color: root.errorState ? Qt.lighter(root.urgent, 1.3) : root.tint(root.fg, 0.6)
        font.family: root.textFont
        font.pixelSize: 12
      }
    }
  }
}
