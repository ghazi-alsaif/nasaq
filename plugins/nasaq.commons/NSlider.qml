import QtQuick
// Pill slider like the control center's MacSlider, with min/max/step and a
// value label. `moved(value)` fires while dragging; `committed(value)` on release.
Item {
  id: s
  property real from: 0
  property real to: 1
  property real stepSize: 0
  property real value: 0
  property string icon: ""
  property string valueText: ""
  signal moved(real value)
  signal committed(real value)
  implicitWidth: 220
  height: 24
  readonly property real frac: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0
  function snap(v) {
    if (stepSize > 0) v = Math.round((v - from) / stepSize) * stepSize + from
    return Math.max(from, Math.min(to, v))
  }
  Rectangle {
    id: track
    anchors.fill: parent
    radius: height / 2
    color: Theme.track
    clip: true
    Rectangle {
      height: parent.height
      width: Math.max(track.height, track.width * s.frac)
      x: Tr.rtl ? track.width - width : 0
      radius: height / 2
      color: Qt.rgba(1, 1, 1, 0.92)
    }
  }
  NGlyph {
    anchors.left: parent.left; anchors.leftMargin: 7
    anchors.verticalCenter: parent.verticalCenter
    text: s.icon; visible: text.length > 0
    color: s.frac > 0.08 ? "#2c2c2e" : "white"
    font.pixelSize: 13
  }
  NSub {
    anchors.right: parent.right; anchors.rightMargin: 9
    anchors.verticalCenter: parent.verticalCenter
    text: s.valueText; visible: text.length > 0
    color: s.frac > 0.85 ? "#2c2c2e" : Theme.subText
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    function apply(x) {
      var f = Math.max(0, Math.min(1, x / track.width))
      if (Tr.rtl) f = 1 - f
      s.moved(s.snap(s.from + f * (s.to - s.from)))
    }
    onPressed: function(e) { apply(e.x) }
    onPositionChanged: function(e) { if (pressed) apply(e.x) }
    onReleased: s.committed(s.value)
  }
}
