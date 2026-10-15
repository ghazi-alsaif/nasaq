import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Hyprland
import qs.Commons

// Compact dropdown: model = [{value, label}] or plain strings.
// The list is its own popup surface (xdg-popup) rather than an item inside the
// settings window, so Hyprland can blur what is behind it: the same glass as
// the island and Quick Settings (popup blur is on in nasaq-looknfeel.lua). It
// opens below the field, or above it when there is no room, never clipped by
// its card. A click outside closes it; a second click on the field closes it
// too (it used to reopen it).
Item {
  id: dd
  property var model: []
  property var value
  readonly property bool open: popup.visible
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

  // shown drives the fade; the surface unmaps after the fade-out.
  property bool shown: false
  property double closedAt: 0
  function openList() { hideTimer.stop(); popup.visible = true; shown = true }
  function closeList() {
    if (!shown) return
    shown = false
    closedAt = Date.now()
    hideTimer.restart()
  }
  Timer { id: hideTimer; interval: Motion.micro + 30; onTriggered: popup.visible = false }

  Rectangle {
    anchors.fill: parent
    radius: 8
    color: Qt.rgba(1, 1, 1, headMouse.containsMouse || dd.shown ? 0.2 : 0.12)
    NLabel { anchors.left: parent.left; anchors.leftMargin: 10; anchors.right: chev.left; anchors.verticalCenter: parent.verticalCenter; text: dd.labelOf(dd.value); font.weight: Font.Normal }
    NGlyph { id: chev; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: dd.shown ? "󰅃" : "󰅀"; font.pixelSize: 12; opacity: 0.7 }
    MouseArea {
      id: headMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        if (dd.shown) { dd.closeList(); return }
        // The press that just closed the list (outside the popup) lands here
        // too; do not reopen it.
        if (Date.now() - dd.closedAt < 300) return
        dd.openList()
      }
    }
  }

  PopupWindow {
    id: popup
    visible: false
    color: "transparent"
    readonly property int listHeight: Math.min(300, list.contentHeight + 8)
    implicitWidth: Math.max(dd.width, 160)
    implicitHeight: listHeight

    anchor {
      id: popupAnchor
      window: dd.QsWindow.window
      adjustment: PopupAdjustment.Slide
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.width: 1
      rect.height: 1
      onAnchoring: {
        var w = dd.QsWindow.window
        if (!w) return
        var below = w.contentItem.mapFromItem(dd, 0, dd.height + 4)
        var above = w.contentItem.mapFromItem(dd, 0, -popup.listHeight - 4)
        var p = below.y + popup.listHeight <= w.height ? below : above
        popupAnchor.rect.x = Math.round(Math.max(0, Math.min(p.x, w.width - popup.implicitWidth)))
        popupAnchor.rect.y = Math.round(Math.max(0, p.y))
      }
    }

    // A click anywhere else (or Escape) closes the list.
    HyprlandFocusGrab {
      active: dd.shown
      windows: [popup]
      onCleared: dd.closeList()
    }

    Rectangle {
      id: card
      anchors.fill: parent
      radius: 10
      // The panels' glass: the theme background at the window opacity
      // (at least 0.55, above Hyprland's popups_ignorealpha so it blurs).
      color: Util.alpha(Color.background, Math.max(0.55, Theme.glassAlpha))
      border.color: Qt.rgba(1, 1, 1, 0.14)
      border.width: 1
      opacity: dd.shown ? 1 : 0
      scale: dd.shown ? 1 : 0.96
      transformOrigin: Item.Top
      Behavior on opacity { NFade { duration: dd.shown ? Motion.fast : Motion.micro } }
      Behavior on scale { NAnim { kind: "fast" } }
      focus: true
      Keys.onEscapePressed: dd.closeList()

      ListView {
        id: list
        anchors.fill: parent
        anchors.margins: 4
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
          MouseArea { id: itemMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { dd.closeList(); dd.activated(parent.v) } }
        }
      }
    }
  }
}
