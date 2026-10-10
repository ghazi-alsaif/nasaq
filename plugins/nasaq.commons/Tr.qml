pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Tiny i18n layer. Tr.t("settings.title") looks the key up in
// ~/.config/omarchy/nasaq/i18n/<language>.json (falls back to the bundled
// i18n/<language>.json next to this file, then English, then the key).
Singleton {
  id: root
  readonly property string language: Settings.get("general.language", "en")
  readonly property bool rtl: {
    var mode = Settings.get("general.rtl", "auto")
    return mode === "on" || (mode === "auto" && language === "ar")
  }
  property var strings: ({})
  property var fallback: ({})
  property int revision: 0

  // Translate an English interface string (NASAQ components call this on
  // every title, subtitle, note, button and option). Unknown strings stay English.
  property var ui: ({})
  function s(text) {
    void revision
    if (language !== "ar" || text === undefined || text === null) return text
    var v = ui[String(text)]
    return v !== undefined ? v : text
  }
  FileView {
    path: root.bundled + "ar-ui.json"
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { root.ui = JSON.parse(text()) } catch (e) { root.ui = {} } root.revision++ }
  }

  function t(key) {
    void revision
    if (strings[key] !== undefined) return strings[key]
    if (fallback[key] !== undefined) return fallback[key]
    return key
  }

  readonly property string bundled: Qt.resolvedUrl("i18n/").toString().replace("file://", "")

  FileView {
    path: root.bundled + root.language + ".json"
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { root.strings = JSON.parse(text()) } catch (e) { root.strings = {} } root.revision++ }
    onLoadFailed: { root.strings = {}; root.revision++ }
  }
  FileView {
    path: root.bundled + "en.json"
    blockLoading: true
    printErrors: false
    onLoaded: { try { root.fallback = JSON.parse(text()) } catch (e) { root.fallback = {} } root.revision++ }
  }
}
