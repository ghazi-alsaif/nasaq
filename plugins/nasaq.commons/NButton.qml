import QtQuick
Rectangle {
  id: b
  property string text: ""
  property string icon: ""
  property bool primary: false
  property bool danger: false
  signal clicked()
  height: 28
  width: Math.max(72, row.implicitWidth + 22)
  radius: 8
  color: primary ? Theme.accent : danger ? (mouse.containsMouse ? Theme.danger : Qt.rgba(1, 0.27, 0.23, 0.25))
         : Qt.rgba(1, 1, 1, mouse.containsMouse ? 0.2 : 0.12)
  Behavior on color { ColorAnimation { duration: Theme.durFast } }
  Row {
    id: row
    anchors.centerIn: parent
    spacing: 6
    NGlyph { text: b.icon; visible: text.length > 0; font.pixelSize: 13; color: b.primary ? Theme.onAccent : "white"; anchors.verticalCenter: parent.verticalCenter }
    NLabel { text: Tr.s(b.text); font.weight: Font.Medium; color: b.primary ? Theme.onAccent : "white"; anchors.verticalCenter: parent.verticalCenter }
  }
  MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
}
