import QtQuick

// Opacity, radius, fill and other non-spatial changes.
NumberAnimation {
  duration: Motion.fast
  easing.type: Easing.BezierSpline
  easing.bezierCurve: Motion.decel
}
