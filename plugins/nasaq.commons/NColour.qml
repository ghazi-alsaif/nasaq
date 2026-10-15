import QtQuick

// Colour changes.
ColorAnimation {
  duration: Motion.colour
  easing.type: Easing.BezierSpline
  easing.bezierCurve: Motion.decel
}
