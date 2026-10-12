import QtQuick
import QtQuick.Window
import SddmComponents 2.0

// NASAQ login screen, in the same look as the NASAQ lock screen:
// blurred wallpaper, big clock, Matrix rain, avatar + password pill, a
// keyboard-layout pill top-right and Sleep / Restart / Shut Down bottom-right.
Rectangle {
  id: root
  width: 1920
  height: 1080
  color: surface

  // Every colour comes from the active Omarchy theme. nasaq-login-sync writes
  // them into theme.conf on each theme change; SDDM hands [General] keys to
  // QML as config.<key>. The fallbacks only apply if a key is missing.
  readonly property color surface: config.surface || "#101012"   // base under the wallpaper
  readonly property color fg: config.fg || "#ffffff"             // text, icons and the glass tint
  readonly property color accent: config.accent || fg            // cursor, selection, avatar
  readonly property color rain: config.rainColor || accent       // Matrix rain
  readonly property color urgent: config.urgent || "#ff6b5e"     // wrong password, armed power button
  function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  // Same physical size as the lock screen: the lock draws these in logical px
  // at the session's monitor scale, which nasaq-login-sync records as uiScale.
  // Divide by the greeter's own pixel ratio. Without it, fall back to height.
  readonly property real s: config.uiScale
    ? Number(config.uiScale) / Math.max(1, Screen.devicePixelRatio)
    : Math.max(0.6, height / 1080)
  readonly property string textFont: "IBM Plex Sans Arabic"
  readonly property string iconFont: "JetBrainsMono Nerd Font"
  readonly property string monoFont: "JetBrains Mono"

  // Last user who logged in, else the first account SDDM lists (NameRole).
  property string currentUser: userModel.lastUser
    || String(userModel.data(userModel.index(0, 0), Qt.UserRole + 1) || "")
  readonly property string displayName: currentUser.length > 0 ? currentUser.charAt(0).toUpperCase() + currentUser.slice(1) : ""
  property bool loginFailed: false
  property bool busy: false
  property var now: new Date()

  property int sessionIndex: {
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
      if (name.indexOf("uwsm") !== -1) return i
    }
    return sessionModel.lastIndex
  }

  function glyph(cp) { return String.fromCodePoint(cp) }

  function doLogin() {
    if (password.text.length === 0 || busy) return
    busy = true
    loginFailed = false
    sddm.login(root.currentUser, password.text, root.sessionIndex)
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      root.busy = false
      root.loginFailed = true
      password.text = ""
      password.forceActiveFocus()
      shake.restart()
    }
    function onLoginSucceeded() { root.loginFailed = false }
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.now = new Date()
  }

  Image {
    anchors.fill: parent
    source: config.background || "background.jpg"
    fillMode: Image.PreserveAspectCrop
    asynchronous: false
  }

  MouseArea {
    anchors.fill: parent
    onClicked: password.forceActiveFocus()
  }

  // ── Date and clock ──
  Column {
    id: clockColumn
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: Math.round(root.height * 0.17)
    spacing: -Math.round(root.height * 0.006)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.locale("en_US").toString(root.now, "dddd, MMMM d")
      color: root.tint(root.fg, 0.9)
      font.family: root.monoFont
      font.weight: Font.Medium
      font.pixelSize: Math.round(root.height * 0.026)
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.locale("en_US").toString(root.now, "h:mm AP").replace(/\s*[AP]M$/i, "")
      color: root.tint(root.fg, 0.95)
      font.family: root.monoFont
      font.weight: Font.Normal
      font.pixelSize: Math.round(root.height * 0.13)
    }
  }

  // ── Matrix rain ──
  MatrixRain {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: loginColumn.bottom
    anchors.topMargin: 10
    anchors.bottom: powerRow.top
    anchors.bottomMargin: 10
    width: Math.min(620, Math.round(root.width * 0.42))
    opacity: 0.85
    color: root.rain
    headColor: Qt.lighter(root.rain, 1.6)
  }

  // ── Keyboard layout pill (top-right) ──
  Rectangle {
    id: kbPill
    readonly property var layouts: keyboard && keyboard.layouts ? keyboard.layouts : []
    readonly property string label: layouts.length > 0 && keyboard.currentLayout < layouts.length
      ? String(layouts[keyboard.currentLayout].shortName || "").toUpperCase() : ""
    visible: label.length > 0
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: 14 * root.s
    height: 34 * root.s
    width: kbRow.implicitWidth + 24 * root.s
    radius: height / 2
    color: root.tint(root.fg, kbMouse.containsMouse ? 0.18 : 0.10)
    Row {
      id: kbRow
      anchors.centerIn: parent
      spacing: 8 * root.s
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.glyph(0xf030c)
        color: root.fg
        font.family: root.iconFont
        font.pixelSize: 15 * root.s
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: kbPill.label
        color: root.fg
        font.family: root.textFont
        font.weight: Font.DemiBold
        font.pixelSize: 13 * root.s
      }
    }
    MouseArea {
      id: kbMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        if (kbPill.layouts.length > 1) keyboard.currentLayout = (keyboard.currentLayout + 1) % kbPill.layouts.length
        password.forceActiveFocus()
      }
    }
  }

  // ── User and password ──
  Column {
    id: loginColumn
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: clockColumn.bottom
    anchors.topMargin: Math.round(root.height * 0.05)
    spacing: 12 * root.s

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: 190 * root.s
      height: 34 * root.s
      radius: height / 2
      color: root.tint(root.fg, 0.20)
      border.color: root.tint(root.fg, 0.22)
      border.width: 1
      Row {
        anchors.centerIn: parent
        spacing: 7 * root.s
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: 18 * root.s
          height: width
          radius: width / 2
          color: root.accent
          Text {
            anchors.centerIn: parent
            text: root.displayName.charAt(0)
            color: root.surface
            font.family: root.monoFont
            font.weight: Font.Bold
            font.pixelSize: 11 * root.s
          }
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.currentUser.toLowerCase()
          color: root.fg
          font.family: root.monoFont
          font.weight: Font.Bold
          font.pixelSize: 14 * root.s
        }
      }
    }

    Item {
      anchors.horizontalCenter: parent.horizontalCenter
      width: 190 * root.s
      height: 34 * root.s

      Rectangle {
        id: field
        width: parent.width
        height: parent.height
        radius: height / 2
        color: root.tint(root.fg, password.activeFocus ? 0.26 : 0.20)
        border.width: 1
        border.color: root.loginFailed ? root.tint(root.urgent, 0.8) : root.tint(root.fg, 0.22)

        TextInput {
          id: password
          anchors.fill: parent
          anchors.leftMargin: 34 * root.s
          anchors.rightMargin: 34 * root.s
          verticalAlignment: TextInput.AlignVCenter
          horizontalAlignment: TextInput.AlignHCenter
          echoMode: TextInput.Password
          passwordCharacter: "●"
          passwordMaskDelay: 0
          color: root.fg
          selectionColor: root.tint(root.accent, 0.45)
          font.family: root.textFont
          font.pixelSize: (text.length > 0 ? 11 : 13) * root.s
          font.letterSpacing: text.length > 0 ? 2 : 0
          clip: true
          focus: true
          enabled: !root.busy
          cursorDelegate: Rectangle { width: 2; color: root.accent; visible: password.activeFocus }
          onTextChanged: if (text.length > 0) root.loginFailed = false
          onAccepted: root.doLogin()
          Keys.onEscapePressed: text = ""
          Component.onCompleted: forceActiveFocus()
        }

        Text {
          anchors.fill: password
          verticalAlignment: Text.AlignVCenter
          visible: password.text.length === 0
          horizontalAlignment: Text.AlignHCenter
          text: root.busy ? "Signing in…" : "Password"
          color: root.tint(root.fg, 0.85)
          font.family: root.monoFont
          font.weight: Font.Bold
          font.pixelSize: 13 * root.s
        }

        Rectangle {
          anchors.right: parent.right
          anchors.rightMargin: 5 * root.s
          anchors.verticalCenter: parent.verticalCenter
          width: 24 * root.s
          height: width
          radius: width / 2
          visible: password.text.length > 0
          color: root.tint(root.fg, submitMouse.containsMouse ? 0.45 : 0.32)
          Text {
            anchors.centerIn: parent
            text: root.glyph(0xf0054)
            color: root.fg
            font.family: root.iconFont
            font.pixelSize: 15 * root.s
          }
          MouseArea {
            id: submitMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.doLogin()
          }
        }
      }

      SequentialAnimation {
        id: shake
        NumberAnimation { target: field; property: "x"; to: -12; duration: 50 }
        NumberAnimation { target: field; property: "x"; to: 12; duration: 70 }
        NumberAnimation { target: field; property: "x"; to: -8; duration: 70 }
        NumberAnimation { target: field; property: "x"; to: 8; duration: 70 }
        NumberAnimation { target: field; property: "x"; to: 0; duration: 50 }
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      height: 16 * root.s
      text: root.loginFailed ? "Incorrect password, try again"
          : (keyboard && keyboard.capsLock ? "Caps Lock is on" : "")
      color: root.loginFailed ? Qt.lighter(root.urgent, 1.3) : root.tint(root.fg, 0.6)
      font.family: root.textFont
      font.pixelSize: 12 * root.s
    }
  }

  // ── Power row (bottom centre), like the lock screen ──
  Column {
    id: powerRow
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Math.round(root.height * 0.08)
    spacing: 8 * root.s
    property string armed: ""
    Timer { id: powerDisarm; interval: 3000; onTriggered: powerRow.armed = "" }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 34 * root.s
      Repeater {
        model: [
          { key: "off", cp: 0xf0425, action: "powerOff", show: sddm.canPowerOff, confirm: true },
          { key: "restart", cp: 0xf0709, action: "reboot", show: sddm.canReboot, confirm: true },
          { key: "sleep", cp: 0xf0f65, action: "suspend", show: sddm.canSuspend, confirm: false }
        ]
        delegate: Text {
          required property var modelData
          visible: modelData.show
          text: root.glyph(modelData.cp)
          color: powerRow.armed === modelData.key ? root.urgent : root.fg
          opacity: pMouse.containsMouse || powerRow.armed === modelData.key ? 1 : 0.82
          scale: pMouse.containsMouse ? 1.12 : 1
          font.family: root.iconFont
          font.pixelSize: 34 * root.s
          Behavior on scale { NumberAnimation { duration: 120 } }
          MouseArea {
            id: pMouse
            anchors.fill: parent
            anchors.margins: -8
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (modelData.confirm && powerRow.armed !== modelData.key) {
                powerRow.armed = modelData.key
                powerDisarm.restart()
                return
              }
              powerRow.armed = ""
              sddm[modelData.action]()
            }
          }
        }
      }
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      height: 14 * root.s
      text: powerRow.armed === "off" ? "Click again to shut down" : powerRow.armed === "restart" ? "Click again to restart" : ""
      color: root.tint(root.fg, 0.8)
      font.family: root.monoFont
      font.pixelSize: 11 * root.s
    }
  }
}
