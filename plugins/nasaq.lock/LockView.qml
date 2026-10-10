import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Ui

// NASAQ: macOS-style lock screen. The open windows (captured just before the
// lock) sit blurred behind a large clock, the password pill sits low and
// centred, and a control-center popover hangs off the top-right status icons.
Item {
  id: root

  property string backgroundPath: ""
  property int backgroundVersion: 0
  property string capturePath: ""
  property int captureVersion: 0
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  property bool syncingPasswordText: false
  property bool useCapture: true
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
  readonly property string iconFont: Style.font.family
  readonly property string userName: {
    var name = Quickshell.env("USER") || ""
    return name.length > 0 ? name.charAt(0).toUpperCase() + name.slice(1) : ""
  }
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
  onCaptureVersionChanged: useCapture = true
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }
  onLoadBackgroundChanged: if (!loadBackground) { controlsOpen = false; displayOpen = false }
  onFailedAttemptsChanged: if (failedAttempts > 0) shake.restart()
  Component.onCompleted: {
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }

  Rectangle {
    anchors.fill: parent
    color: Color.background

    Image {
      id: backdrop
      anchors.fill: parent
      source: !root.loadBackground ? ""
        : (root.useCapture && root.capturePath ? root.fileUrl(root.capturePath, root.captureVersion)
                                               : root.fileUrl(root.backgroundPath, root.backgroundVersion))
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      visible: false
      onStatusChanged: {
        // No snapshot for this screen (or it failed): fall back to the wallpaper.
        if (status === Image.Error && root.useCapture) root.useCapture = false
      }
    }

    MultiEffect {
      anchors.fill: backdrop
      source: backdrop
      autoPaddingEnabled: false
      blurEnabled: true
      blur: 0.5
      blurMax: 64
      blurMultiplier: 1.0
      // Blur only — no colour or brightness shift (the user, 2026-10-06).
      visible: root.loadBackground && backdrop.status === Image.Ready
    }

    // Soft vertical gradient: a touch darker at the top and bottom so the
    // clock and the power row read on any backdrop.
    Rectangle {
      anchors.fill: parent
      visible: false   // gradient off: the user wants the backdrop blurred only
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
        color: Qt.rgba(1, 1, 1, 0.9)
        font.family: root.monoFont
        font.weight: Font.Medium
        font.pixelSize: Math.round(root.height * 0.026)
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.locale("en_US").toString(clockColumn.now, "h:mm AP").replace(/\s*[AP]M$/i, "")
        color: Qt.rgba(1, 1, 1, 0.95)
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
      anchors.bottom: powerRow.top
      anchors.bottomMargin: 10
      width: Math.min(620, Math.round(root.width * 0.42))
      running: root.loadBackground
      opacity: 0.85
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
      color: root.controlsOpen ? Qt.rgba(1, 1, 1, 0.28)
           : (statusMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.10))
      Behavior on color { ColorAnimation { duration: 120 } }

      Row {
        id: statusRow
        anchors.centerIn: parent
        spacing: 14

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: controls.layoutShort
          visible: text.length > 0
          color: "white"
          font.family: root.textFont
          font.weight: Font.DemiBold
          font.pixelSize: 13
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: controls.wifiIcon
          color: "white"
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
            color: "white"
            font.family: root.textFont
            font.pixelSize: 13
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: controls.batteryIcon
            color: "white"
            font.family: root.iconFont
            font.pixelSize: 16
          }
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰔡"
          color: "white"
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
      color: Qt.rgba(1, 1, 1, root.displayOpen ? 0.26 : (displayMouse.containsMouse ? 0.18 : 0.08))
      opacity: root.displayOpen || displayMouse.containsMouse ? 1 : 0.6
      Behavior on color { ColorAnimation { duration: 120 } }
      Behavior on opacity { NumberAnimation { duration: 160 } }

      Text {
        anchors.centerIn: parent
        text: "󰤄"
        color: "white"
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
      color: Qt.rgba(0.11, 0.11, 0.12, 0.66)
      border.color: Qt.rgba(1, 1, 1, 0.14)
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
            color: Qt.rgba(1, 1, 1, 0.75)
            font.family: root.textFont
            font.pixelSize: 13
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.blankLabels[sleepSlider.index]
            color: "white"
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
            color: Qt.rgba(1, 1, 1, 0.18)
          }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: sleepSlider.index * sleepSlider.step
            height: 4
            radius: 2
            color: Qt.rgba(1, 1, 1, 0.9)
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
              color: index <= sleepSlider.index ? Qt.rgba(0.2, 0.2, 0.22, 0.6) : Qt.rgba(1, 1, 1, 0.35)
            }
          }
          Rectangle {
            x: sleepSlider.index * sleepSlider.step - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            height: 18
            radius: 9
            color: "white"
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
            color: Qt.rgba(1, 1, 1, 0.45)
            font.family: root.textFont
            font.pixelSize: 10
          }
          Text {
            anchors.right: parent.right
            text: "Never"
            color: Qt.rgba(1, 1, 1, 0.45)
            font.family: root.textFont
            font.pixelSize: 10
          }
        }

        Rectangle {
          width: parent.width
          height: 34
          radius: 10
          color: Qt.rgba(1, 1, 1, offMouse.containsMouse ? 0.2 : 0.12)
          Behavior on color { ColorAnimation { duration: 120 } }
          Row {
            anchors.centerIn: parent
            spacing: 8
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "󰶐"
              color: "white"
              font.family: root.iconFont
              font.pixelSize: 15
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Turn Off Display Now"
              color: "white"
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
            color: powerRow.armed === modelData.key ? "#ff6b5e" : "white"
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
        color: Qt.rgba(1, 1, 1, 0.8)
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
        color: Qt.rgba(1, 1, 1, 0.20)
        border.color: Qt.rgba(1, 1, 1, 0.22)
        border.width: 1
        Row {
          anchors.centerIn: parent
          spacing: 7
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            height: 18
            radius: 9
            color: Qt.rgba(1, 1, 1, 0.9)
            Text {
              anchors.centerIn: parent
              text: root.userName.charAt(0)
              color: "#2c2c2e"
              font.family: root.monoFont
              font.weight: Font.Bold
              font.pixelSize: 11
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.userName.toLowerCase()
            color: "white"
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
        color: Qt.rgba(1, 1, 1, 0.22)
        border.color: Qt.rgba(1, 1, 1, 0.35)
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
          text: root.userName.charAt(0)
          color: "white"
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
          color: Qt.rgba(1, 1, 1, passwordInput.activeFocus ? 0.26 : 0.20)
          border.width: 1
          border.color: root.errorState ? Qt.rgba(1, 0.45, 0.45, 0.8) : Qt.rgba(1, 1, 1, 0.22)

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
            color: "white"
            selectionColor: Qt.rgba(1, 1, 1, 0.3)
            selectedTextColor: "white"
            font.family: root.textFont
            font.pixelSize: text.length > 0 ? 11 : 13
            font.letterSpacing: text.length > 0 ? 2 : 0
            cursorVisible: activeFocus && root.showPasswordCursor
            cursorDelegate: Rectangle {
              width: 2
              color: "white"
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
            color: Qt.rgba(1, 1, 1, 0.85)
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
            color: passwordInput.text.length > 0 ? Qt.rgba(1, 1, 1, submitMouse.containsMouse ? 0.45 : 0.32) : "transparent"

            Text {
              anchors.centerIn: parent
              text: passwordInput.text.length > 0 ? "󰁔" : "󰈷"
              color: "white"
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
        color: root.errorState ? Qt.rgba(1, 0.75, 0.75, 0.95) : Qt.rgba(1, 1, 1, 0.6)
        font.family: root.textFont
        font.pixelSize: 12
      }
    }
  }
}
