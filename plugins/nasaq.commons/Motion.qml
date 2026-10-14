pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower

// NASAQ motion: one set of durations and curves for every nasaq.* surface, so
// everything opens, closes and fades with the same rhythm. The curves are the
// same ones NASAQ gives Hyprland's windows (hypr/nasaq-looknfeel.lua), so the
// shell and the windows move alike.
//
// Use the components next to this file instead of numbers:
//   Behavior on width   { NAnim {} }                 a panel or card growing
//   Behavior on y       { NAnim { kind: "move" } }   an item sliding in place
//   Behavior on opacity { NFade {} }                 fades, radius, fill
//   Behavior on color   { NColour {} }               colour changes
//
// motion.scale in settings.json: 1 normal, 0.5 "Reduce motion", 0 off.
// Power saver turns motion off by itself.
Singleton {
  id: root

  readonly property bool saver: PowerProfiles.profile === PowerProfile.PowerSaver
  readonly property real scale: saver ? 0 : Math.max(0, Math.min(1.5, Number(Settings.get("motion.scale", 1))))
  readonly property bool enabled: scale > 0

  function ms(base) { return Math.round(base * scale) }

  // Durations by role (ms).
  readonly property int micro:  ms(120)   // hover tint, press feedback
  readonly property int fast:   ms(200)   // fades, radius, text and icon swaps
  readonly property int colour: ms(300)   // colour changes
  readonly property int base:   ms(320)   // slides in place, list moves, size changes
  readonly property int open:   ms(450)   // a panel or card opening
  readonly property int close:  ms(300)   // a panel or card closing
  readonly property int slow:   ms(600)   // lock screen blur-in

  // Curves: [x1, y1, x2, y2, 1, 1] for Easing.BezierSpline.
  readonly property var decel:    [0.23, 1.00, 0.32, 1.00, 1, 1]  // ends slowly; fades and colour
  readonly property var enter:    [0.22, 1.28, 0.36, 1.00, 1, 1]  // nasaqEnter: grows, a hair past, settles
  readonly property var exit:     [0.55, 0.00, 0.75, 0.60, 1, 1]  // nasaqExit: leaves quickly
  readonly property var bounce:   [0.34, 1.56, 0.64, 1.00, 1, 1]  // nasaqBounce: small things only
  readonly property var standard: [0.40, 0.00, 0.20, 1.00, 1, 1]  // moves in place
}
