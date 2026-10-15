import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.Commons
import "Spot.js" as Spot
import "../nasaq.commons" as Nasaq

// NASAQ: Search (apps, windows, files, calculator, agent). `omarchy-shell nasaq.spotlight toggle`.
// One field for apps, files, arithmetic, currency (live rates, SAR by
// default), units and the web. Arabic digits and words work too.
Item {
  id: root

  property var shell: null
  property string omarchyPath: ""

  property bool open: false
  property bool shown: false
  // The card opens at its final size; size changes animate only once it is up
  // (the first open used to grow from the bare search row into the list).
  property bool sizeSettled: false
  onShownChanged: { sizeSettled = false; if (shown) settleTimer.restart() }
  Timer { id: settleTimer; interval: Nasaq.Motion.fast + 40; onTriggered: root.sizeSettled = true }
  property string query: ""
  property int selected: 0
  property var fileHits: []
  property var rates: null
  property var usage: ({})
  property string toast: ""

  readonly property string textFont: "IBM Plex Sans Arabic"
  readonly property string iconFont: Style.font.family
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateFile: home + "/.local/state/nasaq/spotlight.json"

  readonly property var targetScreen: {
    var mon = Hyprland.focusedMonitor
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) if (mon && screens[i].name === mon.name) return screens[i]
    return screens.length > 0 ? screens[0] : null
  }

  function toggle() { open ? close() : show() }
  function show() {
    query = ""
    fileHits = []
    selected = 0
    toast = ""
    open = true
    Qt.callLater(function() { root.shown = true; input.forceActiveFocus() })
    if (!rates || rates.day !== new Date().toDateString()) ratesProc.running = true
  }
  function close() {
    shown = false
    hideTimer.restart()
  }
  Timer { id: hideTimer; interval: Nasaq.Motion.fast + 20; onTriggered: root.open = false }

  // ── qalc: when NASAQ's own calculator cannot read a sum (sqrt(2), 5!,
  // today + 40 days), ask qalc if it is installed. Debounced, never blocks typing.
  property bool hasQalc: false
  property var qalcResult: null      // { q, v }
  Process { running: true; command: ["sh", "-c", "command -v qalc"]; stdout: StdioCollector { onStreamFinished: root.hasQalc = this.text.trim().length > 0 } }
  Timer {
    id: qalcDebounce
    interval: 150
    onTriggered: {
      var q = root.query.trim()
      if (!root.hasQalc || !q || !/[0-9]/.test(q) || /^[?؟~\/]/.test(q) || q.length > 120) return
      if (Spot.calculate(q) !== null || Spot.parseCurrency(q) || Spot.parseUnits(q)) return
      qalcProc.forQ = q
      qalcProc.command = ["qalc", "-t", q]
      qalcProc.running = true
    }
  }
  Process {
    id: qalcProc
    property string forQ: ""
    stdout: StdioCollector {
      onStreamFinished: {
        var v = this.text.trim().split("\n").pop() || ""
        if (v && v !== qalcProc.forQ && !/error|warning|undefined/i.test(v) && v.length < 80) root.qalcResult = { q: qalcProc.forQ, v: v }
      }
    }
  }

  // ── Results ──────────────────────────────────────────────────────
  readonly property var apps: {
    var q = query.trim().toLowerCase()
    var all = DesktopEntries.applications ? DesktopEntries.applications.values : []
    var scored = []
    for (var i = 0; i < all.length; i++) {
      var e = all[i]
      if (!e || e.noDisplay) continue
      var f = usageScore(e.id)
      var s = q ? Spot.appScore(e, q) : f
      if (s > 0) scored.push({ e: e, s: s + (q ? Math.min(20, f) : 0) })
    }
    scored.sort(function(a, b) { return b.s - a.s })
    return scored.slice(0, q ? 6 : 8).map(function(x) { return x.e })
  }

  // Frecency: launches weighted by how recent they are (a week halves them).
  // Old saves stored a bare count; read those as count with no recency.
  function usageScore(id) {
    var u = usage[id]
    if (!u) return 0
    if (typeof u === "number") return u * 0.5
    var ageDays = Math.max(0, (Date.now() - Number(u.last || 0)) / 86400000)
    return Number(u.count || 0) * (1 / (1 + ageDays / 7)) * 2
  }

  // Open windows matching the query (NASAQ Settings > Launcher).
  readonly property bool windowsOn: Nasaq.Settings.get("launcher.windows", true)
  readonly property bool filesOn: Nasaq.Settings.get("launcher.files", true)
  readonly property bool webOn: Nasaq.Settings.get("launcher.web", true)
  readonly property var windowHits: {
    var q = query.trim().toLowerCase()
    if (!q || !windowsOn) return []
    var all = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    var out = []
    for (var i = 0; i < all.length && out.length < 5; i++) {
      var t = all[i]
      var title = String(t.title || ""), app = String(t.appId || "")
      if (title.toLowerCase().indexOf(q) !== -1 || app.toLowerCase().indexOf(q) !== -1) out.push(t)
    }
    return out
  }

  // ── Preview: preview of the selected file (NASAQ Settings > Launcher) ──
  readonly property bool previewOn: Nasaq.Settings.get("launcher.preview", true)
  readonly property var currentItem: results.length ? results[Math.min(selected, results.length - 1)] : null
  readonly property bool showPreview: previewOn && open && currentItem !== null && currentItem.kind === "file"
  property string pvKind: ""      // image | pdf | text | dir | other
  property string pvPath: ""
  property string pvText: ""
  property string pvImage: ""
  property string pvInfo: ""
  function previewKind(path, isDir) {
    if (isDir) return "dir"
    var ext = String(path).split(".").pop().toLowerCase()
    if (["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "avif"].indexOf(ext) !== -1) return "image"
    if (ext === "pdf") return "pdf"
    if (["txt", "md", "json", "jsonc", "qml", "js", "ts", "py", "sh", "lua", "conf", "toml", "yaml", "yml", "csv", "log", "html", "css", "ini", "xml", "rs", "go", "c", "h", "cpp", "rb", "desktop", "service"].indexOf(ext) !== -1) return "text"
    return "other"
  }
  onCurrentItemChanged: previewTimer.restart()
  Timer {
    id: previewTimer
    interval: 120
    onTriggered: {
      if (!root.showPreview) return
      var it = root.currentItem
      root.pvPath = it.data
      root.pvKind = root.previewKind(it.data, it.isDir)
      root.pvText = ""; root.pvImage = ""; root.pvInfo = ""
      if (root.pvKind === "image") root.pvImage = "file://" + it.data
      var cmd = "f=\"$1\"; stat -c '%s %Y' \"$f\" 2>/dev/null | head -1; echo ---; "
      if (root.pvKind === "dir") cmd += "ls -1p \"$f\" 2>/dev/null | head -40"
      else if (root.pvKind === "text") cmd += "head -c 6000 \"$f\""
      else if (root.pvKind === "pdf") cmd += "c=\"${XDG_CACHE_HOME:-$HOME/.cache}/nasaq/quicklook\"; mkdir -p \"$c\"; o=\"$c/$(printf %s \"$f\" | md5sum | cut -c1-16)\"; [ -f \"$o.png\" ] || pdftoppm -png -f 1 -l 1 -scale-to 700 -singlefile \"$f\" \"$o\" 2>/dev/null; echo \"$o.png\""
      previewProc.running = false
      previewProc.command = ["bash", "-c", cmd, "nasaq-quicklook", it.data]
      previewProc.running = true
    }
  }
  Process {
    id: previewProc
    stdout: StdioCollector {
      onStreamFinished: {
        var t = this.text, cut = t.indexOf("---\n")
        var head = cut >= 0 ? t.slice(0, cut).trim().split(" ") : []
        var body = cut >= 0 ? t.slice(cut + 4) : t
        if (head.length === 2) {
          var bytes = Number(head[0]), when = new Date(Number(head[1]) * 1000)
          var size = bytes < 1024 ? bytes + " B" : bytes < 1048576 ? (bytes / 1024).toFixed(1) + " KB" : (bytes / 1048576).toFixed(1) + " MB"
          root.pvInfo = (root.pvKind === "dir" ? "Folder" : size) + "  ·  " + Qt.formatDateTime(when, "d MMM yyyy, h:mm AP")
        }
        if (root.pvKind === "pdf") root.pvImage = "file://" + body.trim()
        else if (root.pvKind === "text" || root.pvKind === "dir") root.pvText = body
      }
    }
  }

  // ── Ask Claude: "? question" (NASAQ Settings > Launcher) ──
  readonly property bool aiOn: Nasaq.Settings.get("launcher.ai", true)
  // Either question mark works: "?" or the Arabic "؟".
  readonly property bool aiMode: aiOn && /^[?؟]\s*\S/.test(query)
  readonly property string aiQuestion: aiMode ? query.replace(/^[?؟]\s*/, "") : ""
  property string agentName: "Claude"
  Process { id: agentNameProc; command: ["nasaq-agent-ask", "--name"]; running: true
    stdout: StdioCollector { onStreamFinished: { var n = this.text.trim(); root.agentName = n ? n.charAt(0).toUpperCase() + n.slice(1) : "Claude" } } }
  Timer { interval: 60000; repeat: true; running: true; onTriggered: agentNameProc.running = true }
  property string aiAsked: ""
  property bool aiBusy: false
  property var aiReply: null
  onAiQuestionChanged: if (aiQuestion !== aiAsked) aiReply = null
  function ask() {
    if (!aiQuestion || aiBusy) return
    aiAsked = aiQuestion; aiBusy = true; aiReply = null
    aiProc.command = ["nasaq-ask", aiQuestion]
    aiProc.running = true
  }
  Process {
    id: aiProc
    stdout: StdioCollector { onStreamFinished: { root.aiBusy = false; try { root.aiReply = JSON.parse(this.text) } catch (e) { root.aiReply = { answer: this.text.trim(), command: null } } } }
  }

  readonly property var instant: {
    var q = query.trim()
    if (!q) return null
    var calc = Spot.calculate(q)
    if (calc !== null) return { title: Spot.formatNumber(calc), subtitle: q + " =", copy: String(Number(calc.toFixed(10))), glyph: "󰃬" }
    var cur = Spot.parseCurrency(q)
    if (cur && rates && rates.r[cur.from] && rates.r[cur.to]) {
      var v = cur.amount / rates.r[cur.from] * rates.r[cur.to]
      return { title: Spot.formatNumber(v) + " " + cur.to,
               subtitle: Spot.formatNumber(cur.amount) + " " + cur.from + "  ·  1 " + cur.from + " = " + Spot.formatNumber(rates.r[cur.to] / rates.r[cur.from]) + " " + cur.to,
               copy: String(Number(v.toFixed(2))), glyph: "󰈀" }
    }
    var u = Spot.parseUnits(q)
    if (u) return { title: Spot.formatNumber(u.value), subtitle: u.label, copy: String(Number(u.value.toFixed(6))), glyph: "󰑭" }
    if (qalcResult && qalcResult.q === q) return { title: qalcResult.v, subtitle: q + " =", copy: qalcResult.v, glyph: "󰃬" }
    return null
  }

  // Typing a path ("~/Documents/", "/etc/ho") lists that folder instead.
  readonly property bool pathMode: /^[~\/]/.test(query.trim())
  property string pathDir: ""

  function fileItem(p) {
    var isDir = p.slice(-1) === "/"
    var clean = isDir ? p.slice(0, -1) : p
    var parent = clean.slice(0, clean.lastIndexOf("/")).replace(home, "~")
    return { kind: "file", isDir: isDir, title: clean.split("/").pop(), subtitle: (isDir ? "Folder · " : "") + (parent || "/"),
             glyph: isDir ? "󰉋" : Spot.fileGlyph(clean), data: clean }
  }

  readonly property var results: {
    var out = []
    if (pathMode) {
      if (pathDir) out.push({ kind: "file", isDir: true, title: "Open “" + (pathDir.replace(/\/$/, "").split("/").pop() || "/") + "”",
                              subtitle: pathDir.replace(home, "~"), glyph: "󰝰", data: pathDir.replace(/\/$/, "") || "/" })
      for (var k = 0; k < fileHits.length; k++) out.push(fileItem(fileHits[k]))
      return out
    }
    if (aiMode) {
      if (aiReply && aiAsked === aiQuestion) {
        out.push({ kind: "ai", title: aiReply.answer || "(no answer)", subtitle: root.agentName + " · Enter copies the answer", glyph: "󰚩", data: aiReply.answer })
        if (aiReply.command) out.push({ kind: "aicmd", title: "Run: " + aiReply.command, subtitle: "Runs only when you press Enter", glyph: "󰆍", data: aiReply.command })
      } else {
        out.push({ kind: "ai", title: aiBusy ? "Thinking…" : "Ask " + agentName + ": " + aiQuestion, subtitle: aiBusy ? agentName + " · this takes a few seconds" : "Enter to ask", glyph: "󰚩", data: null })
      }
      return out
    }
    if (instant) out.push({ kind: "instant", title: instant.title, subtitle: instant.subtitle, glyph: instant.glyph, data: instant })
    for (var i = 0; i < apps.length; i++)
      out.push({ kind: "app", title: apps[i].name, subtitle: apps[i].genericName || apps[i].comment || "", icon: apps[i].icon, data: apps[i] })
    for (var w = 0; w < windowHits.length; w++) {
      var tl = windowHits[w]
      var de = DesktopEntries.heuristicLookup(String(tl.appId || ""))
      out.push({ kind: "window", title: tl.title || tl.appId, subtitle: "Open window · " + (de && de.name ? de.name : tl.appId), icon: de ? de.icon : "", glyph: "󰖯", data: tl })
    }
    if (filesOn) for (var j = 0; j < fileHits.length; j++) out.push(fileItem(fileHits[j]))
    if (webOn && query.trim().length > 0)
      out.push({ kind: "web", title: "Search the web for “" + query.trim() + "”", subtitle: "Google", glyph: "󰖟", data: query.trim() })
    return out
  }

  onQueryChanged: {
    qalcDebounce.restart()
    selected = 0
    fileHits = []
    pathDir = ""
    if (query.trim().length >= 2 || pathMode) fileTimer.restart()
  }

  // Tab on a folder while typing a path steps into it.
  function stepInto(item) {
    if (!item || item.kind !== "file" || !item.isDir) return false
    var t = item.data.replace(home, "~")
    input.text = (t === "/" ? "" : t) + "/"
    return true
  }

  // Shift+Enter: show the file in its folder instead of opening it.
  function reveal(item) {
    if (!item || item.kind !== "file") return activate(item)
    Quickshell.execDetached(["xdg-open", item.data.slice(0, item.data.lastIndexOf("/")) || "/"])
    close()
  }

  function activate(item) {
    if (!item) return
    if (item.kind === "ai") {
      if (item.data === null) { ask(); return }
      Quickshell.execDetached(["wl-copy", item.data]); toast = "Copied"; toastTimer.restart(); return
    }
    if (item.kind === "aicmd") { Quickshell.execDetached(["bash", "-c", item.data]); close(); return }
    if (item.kind === "instant") {
      Quickshell.execDetached(["wl-copy", item.data.copy])
      toast = "Copied " + item.data.copy
      toastTimer.restart()
      return
    }
    if (item.kind === "app") {
      var id = String(item.data.id || "")
      var u = Object.assign({}, usage)
      var prev = u[id]
      u[id] = { count: (typeof prev === "number" ? prev : (prev ? prev.count : 0)) + 1, last: Date.now() }
      usage = u
      stateView.setText(JSON.stringify({ usage: u }) + "\n")
      Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", id + ".desktop"])
    } else if (item.kind === "window") {
      item.data.activate()
    } else if (item.kind === "file") {
      Quickshell.execDetached(["xdg-open", item.data])
    } else if (item.kind === "web") {
      Quickshell.execDetached(["omarchy-launch-browser", "https://www.google.com/search?q=" + encodeURIComponent(item.data)])
    }
    close()
  }

  Timer { id: toastTimer; interval: 900; onTriggered: root.close() }

  // Files and folders under ~ (hidden folders skipped). A query like ".pdf"
  // lists that file type, newest first; anything else matches names
  // (case-insensitive, literal), newest first as well.
  Timer {
    id: fileTimer
    interval: 160
    onTriggered: {
      if (fileProc.running) { fileProc.rerun = true; return }
      root.startFileSearch()
    }
  }

  function startFileSearch() {
    var q = root.query.trim()
    if (root.pathMode) {
      fileProc.forQuery = root.query
      fileProc.command = ["bash", "-c",
        "p=\"$1\"; p=\"${p/#\\~/$HOME}\"; shopt -s nocaseglob nullglob; " +
        "if [[ $p == */ ]]; then dir=\"${p%/}\"; pre=''; else dir=\"$(dirname \"$p\")\"; pre=\"$(basename \"$p\")\"; fi; " +
        "[ -d \"${p%/}\" ] && [[ $p == */ ]] && echo \"@DIR ${p%/}/\"; " +
        "{ for f in \"${dir%/}\"/\"$pre\"*; do [ -d \"$f\" ] && echo \"$f/\"; done; for f in \"${dir%/}\"/\"$pre\"*; do [ -d \"$f\" ] || echo \"$f\"; done; } | head -40",
        "nasaq-path", q]
      fileProc.running = true
      return
    }
    if (q.length < 2) return
    var ext = q.match(/^\.([A-Za-z0-9]{1,8})$/)
    fileProc.forQuery = root.query
    fileProc.command = ["bash", "-c",
      "q=\"$1\"; ext=\"$2\"; " +
      "if [ -n \"$ext\" ]; then fd -i -e \"$ext\" -t f --max-depth 10 --exclude '.*' --exclude node_modules --max-results 400 . \"$HOME\"; " +
      "else fd -i -F --max-depth 10 --exclude '.*' --exclude node_modules --max-results 200 -- \"$q\" \"$HOME\"; fi " +
      "| while IFS= read -r p; do printf '%s\\t%s\\n' \"$(stat -c %Y \"${p%/}\" 2>/dev/null || echo 0)\" \"$p\"; done " +
      "| sort -rn | head -12 | cut -f2-",
      "nasaq-files", q, ext ? ext[1] : ""]
    fileProc.running = true
  }

  Process {
    id: fileProc
    property string forQuery: ""
    property bool rerun: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (fileProc.forQuery !== root.query) return
        var lines = String(text || "").split("\n").filter(function(l) { return l.length > 0 })
        if (lines.length > 0 && lines[0].indexOf("@DIR ") === 0) root.pathDir = lines.shift().slice(5)
        root.fileHits = lines
      }
    }
    onExited: {
      if (rerun) { rerun = false; root.startFileSearch() }
    }
  }

  // Exchange rates, cached for the day.
  Process {
    id: ratesProc
    command: ["bash", "-c",
      "c=\"${XDG_CACHE_HOME:-$HOME/.cache}/nasaq-spotlight\"; mkdir -p \"$c\"; f=\"$c/rates-$(date +%F).json\"; " +
      "[ -s \"$f\" ] || { curl -4 -sf --max-time 10 https://open.er-api.com/v6/latest/USD -o \"$f.tmp\" && jq -e '.result == \"success\"' \"$f.tmp\" >/dev/null && mv \"$f.tmp\" \"$f\"; rm -f \"$f.tmp\"; }; " +
      "[ -s \"$f\" ] && cat \"$f\" || cat $(ls -t \"$c\"/rates-*.json 2>/dev/null | head -1) 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text)
          if (d && d.rates) root.rates = { r: d.rates, day: new Date().toDateString() }
        } catch (e) {}
      }
    }
  }

  FileView {
    id: stateView
    path: root.stateFile
    atomicWrites: true
    printErrors: false
    onLoaded: { try { root.usage = JSON.parse(text()).usage || {} } catch (e) {} }
  }

  IpcHandler {
    target: "nasaq.spotlight"
    function toggle(): string { root.toggle(); return "ok" }
    function open(): string { root.show(); return "ok" }
    function close(): string { root.close(); return "ok" }
    function search(q: string): string { root.show(); root.query = q; input.text = q; return "ok" }
  }

  Text {
    id: aiTitleProbe
    visible: false
    width: 560
    wrapMode: Text.Wrap
    maximumLineCount: 6
    font.family: root.textFont
    font.pixelSize: 14
    text: root.aiReply ? String(root.aiReply.answer || "") : ""
  }

  // ── UI ───────────────────────────────────────────────────────────
  PanelWindow {
    id: win
    screen: root.targetScreen
    visible: root.open
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nasaq-spotlight"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Rectangle {
      id: card
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.round(parent.height * 0.2)
      readonly property int listWidth: Math.min(700, parent.width - 40)
      width: listWidth + (root.showPreview ? 340 : 0)
      height: searchRow.height + (list.count > 0 ? Math.max(list.height, root.showPreview ? 380 : 0) + 9 : 0)
      Behavior on width { enabled: root.sizeSettled; Nasaq.NAnim { kind: "move" } }
      radius: 22
      color: Util.alpha(Color.background, Math.max(0.55, Nasaq.Theme.glassAlpha))
      border.color: Qt.rgba(1, 1, 1, 0.14)
      border.width: 1
      clip: true
      opacity: root.shown ? 1 : 0
      scale: root.shown ? 1 : 0.96
      Behavior on opacity { Nasaq.NFade {} }
      Behavior on scale { Nasaq.NAnim { kind: "fast" } }
      Behavior on height { enabled: root.sizeSettled; Nasaq.NAnim { kind: "move" } }

      MouseArea { anchors.fill: parent }

      Item {
        id: searchRow
        width: parent.width
        height: 62

        Text {
          id: glass
          anchors.left: parent.left
          anchors.leftMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          text: "󰍉"
          color: Qt.rgba(1, 1, 1, 0.55)
          font.family: root.iconFont
          font.pixelSize: 22
        }

        TextInput {
          id: input
          anchors.left: glass.right
          anchors.leftMargin: 14
          anchors.right: parent.right
          anchors.rightMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          color: "white"
          selectionColor: Qt.rgba(1, 1, 1, 0.3)
          font.family: root.textFont
          font.pixelSize: 22
          clip: true
          focus: root.open
          onTextChanged: root.query = text
          Keys.onPressed: function(e) {
            var n = root.results.length
            if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true }
            else if (e.key === Qt.Key_Tab && root.pathMode && root.stepInto(root.results[root.selected])) { e.accepted = true }
            else if ((e.modifiers & Qt.ControlModifier) && (e.key === Qt.Key_J || e.key === Qt.Key_N)) { root.selected = n ? (root.selected + 1) % n : 0; e.accepted = true }
            else if ((e.modifiers & Qt.ControlModifier) && (e.key === Qt.Key_K || e.key === Qt.Key_P)) { root.selected = n ? (root.selected - 1 + n) % n : 0; e.accepted = true }
            else if (e.key === Qt.Key_Down || (e.key === Qt.Key_Tab)) { root.selected = n ? (root.selected + 1) % n : 0; e.accepted = true }
            else if (e.key === Qt.Key_Up || e.key === Qt.Key_Backtab) { root.selected = n ? (root.selected - 1 + n) % n : 0; e.accepted = true }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
              if (e.modifiers & Qt.ShiftModifier) root.reveal(root.results[root.selected])
              else root.activate(root.results[root.selected])
              e.accepted = true
            }
          }
          Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: input.text.length === 0
            text: "Search"
            color: Qt.rgba(1, 1, 1, 0.35)
            font: input.font
          }
        }
        Connections {
          target: root
          function onOpenChanged() { if (root.open) input.text = "" }
        }
      }

      // Preview pane
      Item {
        visible: root.showPreview
        x: card.listWidth
        anchors.top: searchRow.bottom
        anchors.bottom: parent.bottom
        width: 340
        Rectangle { width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.1) }
        Column {
          x: 16; y: 14
          width: parent.width - 32
          spacing: 8
          Item {
            width: parent.width
            height: root.pvImage ? 230 : 0
            visible: height > 0
            Image { anchors.fill: parent; source: root.pvImage; fillMode: Image.PreserveAspectFit; asynchronous: true; sourceSize.width: 600; cache: false }
          }
          Text {
            width: parent.width
            text: root.currentItem && root.currentItem.kind === "file" ? root.currentItem.title : ""
            color: "white"; font.family: root.textFont; font.weight: Font.DemiBold; font.pixelSize: 15
            wrapMode: Text.WrapAnywhere; maximumLineCount: 2; elide: Text.ElideRight
          }
          Text { width: parent.width; text: root.pvInfo; color: Qt.rgba(1, 1, 1, 0.5); font.family: root.textFont; font.pixelSize: 11 }
          Text {
            width: parent.width
            height: Math.min(implicitHeight, 300 - (root.pvImage ? 230 : 0))
            visible: root.pvText.length > 0
            text: root.pvText
            color: Qt.rgba(1, 1, 1, 0.75)
            font.family: root.pvKind === "text" ? "monospace" : root.textFont
            font.pixelSize: 11
            wrapMode: Text.WrapAnywhere
            clip: true
            textFormat: Text.PlainText
          }
          Text { visible: root.pvKind === "other"; text: "No preview · Enter opens it"; color: Qt.rgba(1, 1, 1, 0.4); font.family: root.textFont; font.pixelSize: 12 }
        }
      }

      Rectangle {
        anchors.top: searchRow.bottom
        width: card.listWidth
        height: 1
        color: Qt.rgba(1, 1, 1, 0.1)
        visible: list.count > 0
      }

      ListView {
        id: list
        anchors.top: searchRow.bottom
        anchors.topMargin: 5
        x: 8
        width: card.listWidth - 16
        height: Math.min(contentHeight, 46 * 9)
        model: root.results
        currentIndex: root.selected
        interactive: contentHeight > height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        // One highlight that glides between results instead of each row lighting
        // up. It follows the current row with its own animation: the view's
        // built-in follow snapped here (positionViewAtIndex on every move).
        highlightFollowsCurrentItem: false
        highlight: Rectangle {
          radius: 10
          color: Color.accent
          width: list.width
          y: list.currentItem ? list.currentItem.y : 0
          height: list.currentItem ? list.currentItem.height : 0
          Behavior on y { enabled: root.sizeSettled; Nasaq.NAnim { kind: "fast" } }
          Behavior on height { enabled: root.sizeSettled; Nasaq.NAnim { kind: "fast" } }
        }

        section.property: "kind"
        section.delegate: Item {
          required property string section
          width: list.width
          height: section === "instant" || section === "aicmd" ? 0 : 24
          visible: height > 0
          Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 3
            text: section === "app" ? (root.query.trim() ? "Applications" : "Frequently Used") : section === "ai" || section === "aicmd" ? root.agentName : section === "window" ? "Open Windows" : section === "file" ? "Files" : section === "web" ? "Web" : ""
            color: Qt.rgba(1, 1, 1, 0.45)
            font.family: root.textFont
            font.weight: Font.DemiBold
            font.pixelSize: 11
          }
        }

        delegate: Rectangle {
          id: row
          required property var modelData
          required property int index
          readonly property bool current: index === root.selected
          width: list.width
          height: modelData.kind === "instant" ? 64 : modelData.kind === "ai" ? Math.max(46, aiTitleProbe.lineCount * 20 + 28) : 46
          radius: 10
          color: "transparent"

          Item {
            id: iconBox
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: row.modelData.kind === "instant" ? 40 : 30
            height: width
            IconImage {
              anchors.fill: parent
              readonly property bool hasIcon: row.modelData.kind === "app" || (row.modelData.kind === "window" && !!row.modelData.icon)
              visible: hasIcon
              source: hasIcon ? Quickshell.iconPath(row.modelData.icon || "application-x-executable", "application-x-executable") : ""
            }
            Text {
              anchors.centerIn: parent
              visible: !(row.modelData.kind === "app" || (row.modelData.kind === "window" && !!row.modelData.icon))
              text: row.modelData.glyph || ""
              color: row.current ? "white" : (row.modelData.kind === "instant" ? Color.accent : Qt.rgba(1, 1, 1, 0.75))
              font.family: root.iconFont
              font.pixelSize: row.modelData.kind === "instant" ? 26 : 20
            }
          }

          Column {
            anchors.left: iconBox.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.rightMargin: row.current ? hintRow.width + 22 : 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
              width: parent.width
              horizontalAlignment: row.modelData.kind === "ai" ? Text.AlignAuto : Text.AlignLeft
              text: row.modelData.title
              color: "white"
              wrapMode: row.modelData.kind === "ai" ? Text.Wrap : Text.NoWrap
              maximumLineCount: row.modelData.kind === "ai" ? 6 : 1
              elide: Text.ElideRight
              font.family: root.textFont
              font.pixelSize: row.modelData.kind === "instant" ? 22 : 14
              font.weight: row.modelData.kind === "instant" ? Font.Bold : Font.Normal
            }
            Text {
              width: parent.width
              visible: text.length > 0
              horizontalAlignment: Text.AlignLeft
              text: row.modelData.subtitle || ""
              color: row.current ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(1, 1, 1, 0.5)
              elide: Text.ElideMiddle
              font.family: root.textFont
              font.pixelSize: 11
            }
          }

          Row {
            id: hintRow
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            z: 2
            visible: row.current
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: row.modelData.kind === "instant" ? (root.toast || "↵ Copy")
                  : row.modelData.kind === "file" ? (root.pathMode && row.modelData.isDir ? "⇥ Enter folder · ↵ Open" : "↵ Open · ⇧↵ Show in folder")
                  : "↵"
              color: Qt.rgba(1, 1, 1, 0.85)
              font.family: root.textFont
              font.pixelSize: 11
            }
            // Open the folder that holds this file.
            Rectangle {
              visible: row.modelData.kind === "file"
              anchors.verticalCenter: parent.verticalCenter
              width: 28
              height: 28
              radius: 8
              color: Qt.rgba(1, 1, 1, revealMouse.containsMouse ? 0.3 : 0.16)
              Text {
                anchors.centerIn: parent
                text: "󰉋"
                color: "white"
                font.family: root.iconFont
                font.pixelSize: 15
              }
              MouseArea {
                id: revealMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.reveal(row.modelData)
              }
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.selected = row.index
            onClicked: root.activate(row.modelData)
          }
        }
      }
    }
  }
}
