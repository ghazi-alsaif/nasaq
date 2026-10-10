import QtQuick
import QtQuick.Controls as QQC

// Compact dropdown: model = [{value, label}] or plain strings.
// The list opens in the window's overlay layer, so it is never hidden by
// the rows below it and never clipped by its card; it opens upward when
// there is no room below.
Item {
  id: dd
  property var model: []
  property var value
  property bool open: popup.visible
  signal activated(var value)
  width: 200
  height: 28
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
    color: Qt.rgba(1, 1, 1, headMouse.containsMouse || popup.visible ? 0.2 : 0.12)
    NLabel { anchors.left: parent.left; anchors.leftMargin: 10; anchors.right: chev.left; anchors.verticalCenter: parent.verticalCenter; text: dd.labelOf(dd.value); font.weight: Font.Normal }
    NGlyph { id: chev; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: popup.visible ? "󰅃" : "󰅀"; font.pixelSize: 12; opacity: 0.7 }
    MouseArea { id: headMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: popup.visible ? popup.close() : popup.open() }
  }
  QQC.Popup {
    id: popup
    parent: QQC.Overlay.overlay
    readonly property int listHeight: Math.min(300, list.contentHeight + 8)
    width: Math.max(dd.width, 160)
    height: listHeight
    // Positioned when it opens (mapToItem is not a live binding).
    onAboutToShow: {
      var ov = QQC.Overlay.overlay
      var o = dd.mapToItem(ov, 0, 0)
      var ovW = ov ? ov.width : dd.Window.width, ovH = ov ? ov.height : dd.Window.height
      var below = o.y + dd.height + 4 + listHeight <= ovH
      x = Math.max(0, Math.min(o.x, ovW - width))
      y = below ? o.y + dd.height + 4 : Math.max(0, o.y - listHeight - 4)
    }
    padding: 4
    modal: false
    closePolicy: QQC.Popup.CloseOnEscape | QQC.Popup.CloseOnPressOutside
    background: Rectangle {
      radius: 10
      color: Qt.rgba(0.13, 0.13, 0.15, 1)
      border.color: Qt.rgba(1, 1, 1, 0.14)
      border.width: 1
    }
    contentItem: ListView {
      id: list
      clip: true
      model: dd.model
      boundsBehavior: Flickable.StopAtBounds
      QQC.ScrollBar.vertical: QQC.ScrollBar { policy: list.contentHeight > list.height ? QQC.ScrollBar.AlwaysOn : QQC.ScrollBar.AlwaysOff }
      delegate: Rectangle {
        required property var modelData
        readonly property var v: (typeof modelData === "object") ? modelData.value : modelData
        width: list.width; height: 30; radius: 6
        color: itemMouse.containsMouse ? Theme.hover : (v === dd.value ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
        NLabel { anchors.left: parent.left; anchors.leftMargin: 8; anchors.right: tick.left; anchors.verticalCenter: parent.verticalCenter; text: Tr.s((typeof modelData === "object") ? modelData.label : modelData); font.weight: Font.Normal }
        NGlyph { id: tick; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: "󰄬"; visible: parent.v === dd.value; color: Theme.accent; font.pixelSize: 12 }
        MouseArea { id: itemMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { popup.close(); dd.activated(parent.v) } }
      }
    }
  }
}
