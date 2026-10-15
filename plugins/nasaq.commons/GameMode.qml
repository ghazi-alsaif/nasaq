import QtQuick
import Quickshell
import Quickshell.Io

// True while NASAQ's game mode is on (nasaq.power owns it and writes
// ~/.local/state/nasaq/gamemode), so other parts can stay out of the way.
// Usage: Nasaq.GameMode { id: game }  then  game.active
Item {
  id: root
  visible: false
  property bool active: false
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/nasaq/gamemode"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.active = text().trim() === "1"
    onLoadFailed: root.active = false
  }
}
