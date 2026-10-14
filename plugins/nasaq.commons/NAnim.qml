import QtQuick

// Spatial motion (position and size). kind: "open" (default), "close",
// "move" (in place), "fast" (small things).
NumberAnimation {
  property string kind: "open"
  duration: kind === "close" ? Motion.close : kind === "move" ? Motion.base : kind === "fast" ? Motion.fast : Motion.open
  easing.type: Easing.BezierSpline
  easing.bezierCurve: kind === "close" ? Motion.exit : kind === "move" ? Motion.standard : kind === "fast" ? Motion.decel : Motion.enter
}
