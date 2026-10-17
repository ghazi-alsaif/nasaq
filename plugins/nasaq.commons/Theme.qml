pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as QsCommons

// NASAQ visual identity, shared by every nasaq.* surface: one glass, one set
// of text tints, one panel radius, one font. Everything follows the active
// Omarchy theme (Color.*), so a light theme gets dark text on light glass,
// and the window opacity chosen in Quick Settings > Windows (nasaq/windows.json).
Singleton {
  id: root

  readonly property string textFont: Settings.get("appearance.textFont", "IBM Plex Sans Arabic")
  readonly property string iconFont: QsCommons.Style.font.family

  readonly property color accent: QsCommons.Color.accent
  readonly property color urgent: QsCommons.Color.urgent
  readonly property color onAccent: (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.6 ? "#16181d" : "white"
  // Text and lines: the theme's foreground at a few set strengths.
  readonly property color text: QsCommons.Color.foreground
  readonly property color subText: Qt.alpha(text, 0.6)
  readonly property color faint: Qt.alpha(text, 0.35)
  readonly property color tile: Qt.alpha(text, 0.08)
  readonly property color tileBorder: Qt.alpha(text, 0.06)
  readonly property color hover: Qt.alpha(text, 0.08)
  readonly property color divider: Qt.alpha(text, 0.12)
  readonly property color track: Qt.alpha(text, 0.16)
  readonly property color danger: QsCommons.Color.urgent
  // No theme carries a "warning" colour: a warm step between urgent and the text.
  readonly property color warn: Qt.tint(QsCommons.Color.urgent, Qt.alpha(text, 0.45))
  readonly property color ok: QsCommons.Color.accent

  // Glass: the theme background at the user's window opacity, never below
  // 0.55 so text stays readable; the solid kind (settings window, menus,
  // cover placeholders) never below 0.8.
  property real glassAlpha: 0.65
  readonly property color glass: Qt.alpha(QsCommons.Color.background, Math.max(0.55, glassAlpha))
  readonly property color glassSolid: Qt.alpha(QsCommons.Color.background, Math.max(0.8, glassAlpha))

  readonly property int radiusPanel: 24   // panels and cards (island, Quick Settings, Search, desktop cards…)
  readonly property int radius: 14        // tiles inside them
  readonly property int radiusSmall: 8
  readonly property int spacing: 8
  readonly property int spacingLarge: 16
  readonly property int fontSize: 13
  readonly property int fontSizeSmall: 11
  readonly property int fontSizeTitle: 15
  readonly property int durFast: Motion.fast      // NButton/NSwitch: same rhythm as everything else
  readonly property int durNormal: Motion.base
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
