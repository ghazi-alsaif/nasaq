import QtQuick
// A scrollable settings page with a title. Put NSection blocks inside.
Flickable {
  id: page
  property string title: ""
  property string subtitle: ""
  default property alias content: col.data
  contentWidth: width
  contentHeight: col.implicitHeight + 40
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  LayoutMirroring.enabled: Tr.rtl
  LayoutMirroring.childrenInherit: true
  Column {
    id: col
    x: 28
    y: 24
    width: page.width - 56
    spacing: 18
    Column {
      width: parent.width
      spacing: 4
      NLabel { width: parent.width; text: Tr.s(page.title); font.pixelSize: 22; font.weight: Font.Bold }
      NSub { width: parent.width; text: Tr.s(page.subtitle); visible: text.length > 0; font.pixelSize: 12 }
    }
  }
}
