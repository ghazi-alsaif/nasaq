pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as QsCommons

// NASAQ visual identity: the control center's glass look, shared by every
// nasaq.* surface. Colours follow the active Omarchy theme (accent) and the
// window opacity chosen in Quick Settings > Windows (nasaq/windows.json).
Singleton {
  id: root

  readonly property string textFont: Settings.get("appearance.textFont", "IBM Plex Sans Arabic")
  readonly property string iconFont: QsCommons.Style.font.family

  readonly property color accent: QsCommons.Color.accent
  readonly property color urgent: QsCommons.Color.urgent
  readonly property color onAccent: (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.6 ? "#16181d" : "white"
  readonly property color text: "white"
  readonly property color subText: Qt.rgba(1, 1, 1, 0.6)
  readonly property color faint: Qt.rgba(1, 1, 1, 0.35)
  readonly property color tile: Qt.rgba(1, 1, 1, 0.08)
  readonly property color tileBorder: Qt.rgba(1, 1, 1, 0.06)
  readonly property color hover: Qt.rgba(1, 1, 1, 0.08)
  readonly property color divider: Qt.rgba(1, 1, 1, 0.12)
  readonly property color track: Qt.rgba(1, 1, 1, 0.16)
  readonly property color danger: "#ff453a"

  // Card glass: same alpha as the user's active windows, never below 0.2.
  property real glassAlpha: 0.65
  readonly property color glass: Qt.rgba(0.11, 0.11, 0.12, glassAlpha)

  readonly property int radius: 14
  readonly property int radiusSmall: 8
  readonly property int spacing: 8
  readonly property int spacingLarge: 16
  readonly property int fontSize: 13
  readonly property int fontSizeSmall: 11
  readonly property int fontSizeTitle: 15
  readonly property int durFast: 140
  readonly property int durNormal: 220
  readonly property int easing: Easing.OutCubic

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/nasaq/windows.json"
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try { var a = Number(JSON.parse(text()).activeOpacity); if (isFinite(a)) root.glassAlpha = Math.max(0.2, Math.min(1, a)) } catch (e) {}
    }
  }
}
