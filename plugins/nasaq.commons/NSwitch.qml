import QtQuick
// Pill switch (same as the quick settings').
Rectangle {
  id: sw
  property bool checked: false
  property bool enabledState: true
  signal toggled(bool checked)
  width: 38; height: 22; radius: 11
  opacity: enabledState ? 1 : 0.4
  color: checked ? Theme.accent : Qt.alpha(Theme.text, 0.22)
  Behavior on color { ColorAnimation { duration: Theme.durFast } }
  Rectangle {
    width: 18; height: 18; radius: 9; y: 2
    x: sw.checked ? sw.width - width - 2 : 2
    color: "white"
    Behavior on x { NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic } }
  }
  MouseArea {
    anchors.fill: parent
    enabled: sw.enabledState
    cursorShape: Qt.PointingHandCursor
    onClicked: sw.toggled(!sw.checked)
  }
}
