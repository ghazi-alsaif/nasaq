import QtQuick

// NASAQ: looping Matrix "digital rain" for the login screen. Each column is a
// falling trail of glyphs with a bright head; the whole band fades to
// transparent at the top and bottom (and softly at the sides) so it melts into
// the blurred backdrop.
Canvas {
  id: rain

  property bool running: true
  property color color: "#3dff7a"
  property color headColor: "#e8ffe8"
  property int fontSize: 15
  property real fadeV: 0.28      // fraction of the height faded at each end
  property real fadeH: 0.10      // fraction of the width faded at each side
  property int frameMs: 55

  readonly property string glyphs: "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ012345789Z:.=*+-<>¦"
  readonly property int cols: Math.max(1, Math.floor(width / fontSize))
  readonly property int rows: Math.max(1, Math.floor(height / fontSize))
  property var drops: []

  renderTarget: Canvas.FramebufferObject

  function randomGlyph() {
    return glyphs.charAt(Math.floor(Math.random() * glyphs.length))
  }

  function newDrop(initial) {
    var chars = []
    for (var r = 0; r < rows; r++) chars.push(randomGlyph())
    return {
      y: initial ? Math.random() * rows * 1.5 - rows * 0.5 : -Math.random() * rows * 0.6,
      speed: 0.25 + Math.random() * 0.55,
      len: 6 + Math.floor(Math.random() * Math.max(6, rows * 0.55)),
      chars: chars
    }
  }

  function reset() {
    var next = []
    for (var c = 0; c < cols; c++) next.push(newDrop(true))
    drops = next
    requestPaint()
  }

  onColsChanged: reset()
  onRowsChanged: reset()
  Component.onCompleted: reset()

  Timer {
    interval: rain.frameMs
    repeat: true
    running: rain.running && rain.visible && rain.width > 0
    onTriggered: {
      var d = rain.drops
      for (var c = 0; c < d.length; c++) {
        var drop = d[c]
        drop.y += drop.speed
        // A few glyphs in each trail flicker to new symbols.
        if (Math.random() < 0.3) drop.chars[Math.floor(Math.random() * drop.chars.length)] = rain.randomGlyph()
        if (drop.y - drop.len > rain.rows) d[c] = rain.newDrop(false)
      }
      rain.requestPaint()
    }
  }

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    ctx.clearRect(0, 0, width, height)
    ctx.font = fontSize + "px 'Noto Sans CJK JP', 'Noto Sans CJK TC', monospace"
    ctx.textAlign = "center"

    var xOffset = (width - cols * fontSize) / 2 + fontSize / 2
    for (var c = 0; c < drops.length; c++) {
      var drop = drops[c]
      var head = Math.floor(drop.y)
      for (var k = 0; k < drop.len; k++) {
        var row = head - k
        if (row < 0 || row >= rows) continue
        var a = k === 0 ? 1.0 : Math.pow(1 - k / drop.len, 1.4) * 0.85
        var col = k === 0 ? headColor : color
        ctx.fillStyle = Qt.rgba(col.r, col.g, col.b, a)
        ctx.fillText(drop.chars[row % drop.chars.length], xOffset + c * fontSize, (row + 1) * fontSize)
      }
    }

    // Fade the band's edges: keep only what's under the gradient masks.
    ctx.globalCompositeOperation = "destination-in"
    var gv = ctx.createLinearGradient(0, 0, 0, height)
    gv.addColorStop(0, Qt.rgba(0, 0, 0, 0))
    gv.addColorStop(fadeV, Qt.rgba(0, 0, 0, 1))
    gv.addColorStop(1 - fadeV, Qt.rgba(0, 0, 0, 1))
    gv.addColorStop(1, Qt.rgba(0, 0, 0, 0))
    ctx.fillStyle = gv
    ctx.fillRect(0, 0, width, height)

    var gh = ctx.createLinearGradient(0, 0, width, 0)
    gh.addColorStop(0, Qt.rgba(0, 0, 0, 0))
    gh.addColorStop(fadeH, Qt.rgba(0, 0, 0, 1))
    gh.addColorStop(1 - fadeH, Qt.rgba(0, 0, 0, 1))
    gh.addColorStop(1, Qt.rgba(0, 0, 0, 0))
    ctx.fillStyle = gh
    ctx.fillRect(0, 0, width, height)
    ctx.globalCompositeOperation = "source-over"
  }
}
