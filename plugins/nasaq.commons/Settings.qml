pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// One live settings file for everything NASAQ owns that Omarchy does not:
// ~/.config/omarchy/nasaq/settings.json. Reads are synchronous; writes are
// debounced (300 ms) and merged, so many controls can write at once.
Singleton {
  id: root
  readonly property string dir: Quickshell.env("HOME") + "/.config/omarchy/nasaq"
  readonly property string path: dir + "/settings.json"
  property var data: ({})
  property int revision: 0          // bump on every change; bind to it to re-read
  property bool loaded: false

  readonly property var defaults: ({
    "general": { "language": "en", "rtl": "auto" },
    "appearance": { "textFont": "IBM Plex Sans Arabic" },
    "island": { "hijri": "both" },
    "notifications": { "duration": 8, "groupByApp": true, "rules": [] },
    "hotCorners": { "tl": "none", "tr": "none", "bl": "none", "br": "none", "delay": 150 },
    "switcher": { "enabled": true },
    "scratchpads": [{ "name": "term", "command": "ptyxis --standalone --new-window -T 'NASAQ Scratch'", "title": "NASAQ Scratch", "key": "SUPER + code:49", "width": 1400, "height": 760 }],
    "temps": { "warn": 60, "hot": 80 },
    "ocr": { "languages": "ara+eng" },
    "translate": { "target": "auto" },
    "plugins": { "off": [] },
    "bars": { "extraLaunchers": [] },
    "automations": []
  })

  function _walk(obj, key) {
    var parts = key.split(".")
    var cur = obj
    for (var i = 0; i < parts.length; i++) {
      if (cur === null || cur === undefined || typeof cur !== "object") return undefined
      cur = cur[parts[i]]
    }
    return cur
  }

  // get("notifications.duration", 8). Reading `revision` makes bindings live.
  function get(key, fallback) {
    void revision
    var v = _walk(data, key)
    if (v === undefined) v = _walk(defaults, key)
    return v === undefined ? fallback : v
  }

  function set(key, value) {
    var parts = key.split(".")
    var next = JSON.parse(JSON.stringify(data || {}))
    var cur = next
    for (var i = 0; i < parts.length - 1; i++) {
      if (typeof cur[parts[i]] !== "object" || cur[parts[i]] === null || Array.isArray(cur[parts[i]])) cur[parts[i]] = {}
      cur = cur[parts[i]]
    }
    cur[parts[parts.length - 1]] = value
    data = next
    revision++
    saveTimer.restart()
  }

  Timer {
    id: saveTimer
    interval: 300
    onTriggered: {
      file.setText(JSON.stringify(root.data, null, 2) + "\n")
    }
  }

  FileView {
    id: file
    path: root.path
    blockLoading: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try { root.data = JSON.parse(text()) || {} } catch (e) { console.warn("nasaq: settings.json is not valid JSON; keeping previous values") }
      root.loaded = true
      root.revision++
    }
    onLoadFailed: function(err) {
      // First run: write the defaults so the file is discoverable and editable.
      root.data = JSON.parse(JSON.stringify(root.defaults))
      root.loaded = true
      root.revision++
      Quickshell.execDetached(["mkdir", "-p", root.dir])
      saveTimer.restart()
    }
  }
}
