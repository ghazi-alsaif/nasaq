import QtQuick
// Compact dropdown: model = [{value, label}] or plain strings.
Item {
  id: dd
  property var model: []
  property var value
  property bool open: false
  signal activated(var value)
  width: 200
  height: 28
  z: open ? 100 : 0
  function labelOf(v) {
    for (var i = 0; i < model.length; i++) {
      var m = model[i]; var mv = (typeof m === "object") ? m.value : m
      if (mv === v) return Tr.s((typeof m === "object") ? m.label : m)
    }
    return v === undefined ? "" : String(v)
  }
  Rectangle {
    anchors.fill: parent
    radius: 8
    color: Qt.rgba(1, 1, 1, headMouse.containsMouse || dd.open ? 0.2 : 0.12)
    NLabel { anchors.left: parent.left; anchors.leftMargin: 10; anchors.right: chev.left; anchors.verticalCenter: parent.verticalCenter; text: dd.labelOf(dd.value); font.weight: Font.Normal }
    NGlyph { id: chev; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: dd.open ? "󰅃" : "󰅀"; font.pixelSize: 12; opacity: 0.7 }
    MouseArea { id: headMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dd.open = !dd.open }
  }
  Rectangle {
    visible: dd.open
    y: dd.height + 4
    width: dd.width
    height: Math.min(260, list.contentHeight + 8)
    radius: 10
    color: Qt.rgba(0.16, 0.16, 0.18, 0.98)
    border.color: Theme.tileBorder
    ListView {
      id: list
      anchors.fill: parent; anchors.margins: 4
      clip: true
      model: dd.model
      delegate: Rectangle {
        required property var modelData
        readonly property var v: (typeof modelData === "object") ? modelData.value : modelData
        width: list.width; height: 28; radius: 6
        color: itemMouse.containsMouse ? Theme.hover : (v === dd.value ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
        NLabel { anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: Tr.s((typeof modelData === "object") ? modelData.label : modelData); font.weight: Font.Normal }
        NGlyph { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: "󰄬"; visible: parent.v === dd.value; color: Theme.accent; font.pixelSize: 12 }
        MouseArea { id: itemMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { dd.open = false; dd.activated(parent.v) } }
      }
    }
  }
}
