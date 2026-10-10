import QtQuick
// Captures a key combination as Hyprland Lua text using keycodes
// ("SUPER + ALT + code:39"), so bindings survive the Arabic layout.
Rectangle {
  id: kf
  property string combo: ""
  property bool capturing: false
  signal captured(string combo)
  width: 220; height: 28; radius: 8
  color: capturing ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.12)
  border.color: capturing ? Theme.accent : "transparent"
  NLabel {
    anchors.centerIn: parent
    text: kf.capturing ? Tr.s("Press keys… (Esc cancels)") : (kf.combo || Tr.s("Click to set"))
    font.weight: Font.Normal
    color: kf.combo || kf.capturing ? Theme.text : Theme.faint
  }
  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { kf.capturing = true; catcher.forceActiveFocus() } }
  Item {
    id: catcher
    focus: kf.capturing
    Keys.onPressed: function(e) {
      if (!kf.capturing) return
      e.accepted = true
      if (e.key === Qt.Key_Escape) { kf.capturing = false; return }
      var modKeys = [Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_Meta, Qt.Key_Control, Qt.Key_Shift, Qt.Key_Alt, Qt.Key_AltGr]
      if (modKeys.indexOf(e.key) !== -1) return
      var mods = []
      if (e.modifiers & Qt.MetaModifier) mods.push("SUPER")
      if (e.modifiers & Qt.ControlModifier) mods.push("CTRL")
      if (e.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
      if (e.modifiers & Qt.AltModifier) mods.push("ALT")
      // nativeScanCode is the evdev code + 8 = the xkb keycode Hyprland expects.
      mods.push("code:" + e.nativeScanCode)
      kf.combo = mods.join(" + ")
      kf.capturing = false
      kf.captured(kf.combo)
    }
  }
}
