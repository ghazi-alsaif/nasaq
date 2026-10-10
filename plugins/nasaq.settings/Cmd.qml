import QtQuick
import Quickshell
import Quickshell.Io

// Runs a bash snippet and keeps its trimmed stdout. `refresh()` re-runs it.
Process {
  id: p
  property string script: ""
  property string out: ""
  property bool autoRun: true
  signal done(string out)
  command: ["bash", "-c", script]
  stdout: StdioCollector { onStreamFinished: { p.out = this.text.trim(); p.done(p.out) } }
  function refresh() { running = false; running = true }
  Component.onCompleted: if (autoRun && script.length) running = true
}
