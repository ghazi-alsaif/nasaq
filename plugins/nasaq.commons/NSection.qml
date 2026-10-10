import QtQuick
// A titled group card. Children stack vertically.
Column {
  id: sec
  property string title: ""
  property string note: ""
  default property alias content: body.data
  width: parent ? parent.width : 400
  spacing: 6
  Text {
    text: Tr.s(sec.title); visible: text.length > 0
    color: Qt.rgba(1, 1, 1, 0.5)
    font.family: Theme.textFont; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.DemiBold
    leftPadding: 4; rightPadding: 4
    width: parent.width
    horizontalAlignment: Text.AlignLeft
  }
  NCard {
    width: parent.width
    height: body.implicitHeight + 8
    Column { id: body; x: 14; y: 4; width: parent.width - 28 }
  }
  NSub { text: Tr.s(sec.note); visible: text.length > 0; width: parent.width; leftPadding: 4; rightPadding: 4 }
}
