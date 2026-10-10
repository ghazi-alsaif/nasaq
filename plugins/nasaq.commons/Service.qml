import QtQuick
import Quickshell
import Quickshell.Io

// Keeps the NASAQ singletons alive for the whole session and exposes them
// over IPC:  omarchy-shell nasaq get notifications.duration
//            omarchy-shell nasaq set notifications.duration 7
Item {
  id: root
  readonly property bool ready: Settings.loaded
  readonly property string accentProbe: Theme.accent
  readonly property string lang: Tr.language

  IpcHandler {
    target: "nasaq"
    function get(key: string): string { var v = Settings.get(key, null); return JSON.stringify(v) }
    function set(key: string, json: string): string {
      var v
      try { v = JSON.parse(json) } catch (e) { v = json }
      Settings.set(key, v)
      return "ok"
    }
    function reload(): void { Settings.revision++ }
    function ping(): string { return "nasaq " + (Settings.loaded ? "ready" : "loading") + " · lang=" + Tr.language + " · rtl=" + Tr.rtl }
  }
}
