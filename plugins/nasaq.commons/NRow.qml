import QtQuick
// A settings row: title + optional subtitle on one side, any control on the other.
//   NRow { title: "Duration"; subtitle: "Seconds"; NSlider { … } }
Item {
  id: row
  property string title: ""
  property string subtitle: ""
  default property alias control: slot.data
  width: parent ? parent.width : 400
  height: Math.max(44, texts.implicitHeight + 16, slot.childrenRect.height + 16)
  Column {
    id: texts
    anchors.left: parent.left
    anchors.right: slot.left
    anchors.rightMargin: Theme.spacingLarge
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2
    NLabel { width: parent.width; text: Tr.s(row.title); font.weight: Font.Normal }
    NSub { width: parent.width; text: Tr.s(row.subtitle); visible: text.length > 0 }
  }
  Item {
    id: slot
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: childrenRect.width
    height: childrenRect.height
  }
  Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.divider; opacity: 0.6 }
}
