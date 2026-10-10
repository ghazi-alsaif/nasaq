// NASAQ: Spotlight helpers — calculator, currency and unit conversion, app ranking.

function normalizeDigits(s) {
  return String(s || "")
    .replace(/[٠-٩]/g, function(d) { return String(d.charCodeAt(0) - 0x0660) })
    .replace(/[۰-۹]/g, function(d) { return String(d.charCodeAt(0) - 0x06F0) })
    .replace(/٫/g, ".").replace(/٬/g, ",")
}

function formatNumber(n) {
  if (!isFinite(n)) return String(n)
  var abs = Math.abs(n)
  var digits = abs >= 1000 ? 2 : abs >= 1 ? 4 : 6
  var fixed = Number(n.toFixed(digits))
  var parts = String(fixed).split(".")
  parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  return parts.join(".")
}

// Plain arithmetic only: the character set is checked before evaluating.
function calculate(raw) {
  var q = normalizeDigits(raw).trim().replace(/×/g, "*").replace(/÷/g, "/").replace(/,/g, "")
  if (!/^[\d\s+\-*/().%^]+$/.test(q)) return null
  if (!/\d/.test(q) || !/[+\-*/%^]/.test(q.replace(/^-/, ""))) return null
  q = q.replace(/\^/g, "**")
  try {
    var v = Function("\"use strict\"; return (" + q + ")")()
    if (typeof v !== "number" || !isFinite(v)) return null
    return v
  } catch (e) {
    return null
  }
}

var currencyAliases = {
  "$": "USD", "usd": "USD", "dollar": "USD", "dollars": "USD", "دولار": "USD",
  "sar": "SAR", "riyal": "SAR", "riyals": "SAR", "ريال": "SAR", "ر.س": "SAR", "رس": "SAR",
  "€": "EUR", "eur": "EUR", "euro": "EUR", "يورو": "EUR",
  "£": "GBP", "gbp": "GBP", "pound": "GBP", "جنيه": "GBP",
  "aed": "AED", "درهم": "AED", "kwd": "KWD", "دينار": "KWD", "egp": "EGP", "qar": "QAR",
  "bhd": "BHD", "omr": "OMR", "jod": "JOD", "try": "TRY", "jpy": "JPY", "¥": "JPY",
  "cny": "CNY", "inr": "INR", "cad": "CAD", "aud": "AUD", "chf": "CHF", "btc": "BTC"
}

function currencyCode(token) {
  var t = String(token || "").toLowerCase().trim()
  if (!t) return ""
  if (currencyAliases[t]) return currencyAliases[t]
  if (/^[a-z]{3}$/.test(t)) return t.toUpperCase()
  return ""
}

// "100 usd", "100$", "$100", "100 usd to eur", "٥٠ ريال بالدولار"
function parseCurrency(raw) {
  var q = normalizeDigits(raw).trim().replace(/,/g, "")
  var m = q.match(/^([$€£¥])?\s*(\d+(?:\.\d+)?)\s*([^\d\s]+)?(?:\s+(?:to|in|=|الى|إلى|ب|بال)\s*)?\s*([^\d\s]+)?$/i)
  if (!m) return null
  var amount = parseFloat(m[2])
  var fromTok = m[1] || m[3] || ""
  var toTok = m[1] ? (m[3] || m[4] || "") : (m[4] || "")
  toTok = String(toTok).replace(/^بال/, "").replace(/^ب/, "")
  var from = currencyCode(fromTok)
  if (!from) return null
  var to = currencyCode(toTok)
  if (toTok && !to) return null
  if (!to) to = from === "SAR" ? "USD" : "SAR"
  if (to === from) return null
  return { amount: amount, from: from, to: to }
}

var units = {
  length: { m: 1, km: 1000, cm: 0.01, mm: 0.001, mi: 1609.344, ft: 0.3048, "in": 0.0254, yd: 0.9144,
            "م": 1, "كم": 1000, "سم": 0.01, "مم": 0.001, "ميل": 1609.344, "قدم": 0.3048, "انش": 0.0254 },
  mass: { kg: 1, g: 0.001, lb: 0.45359237, oz: 0.028349523, t: 1000, "كجم": 1, "كيلو": 1, "غ": 0.001, "جرام": 0.001, "رطل": 0.45359237 },
  volume: { l: 1, ml: 0.001, gal: 3.785411784, "لتر": 1 }
}
var unitDefaults = { km: "mi", mi: "km", m: "ft", ft: "m", cm: "in", "in": "cm", kg: "lb", lb: "kg", g: "oz", oz: "g",
                     l: "gal", gal: "l", "كم": "mi", "كيلو": "lb", "كجم": "lb", "سم": "in" }

function unitGroup(u) {
  for (var g in units) if (units[g][u] !== undefined) return g
  return ""
}

function parseUnits(raw) {
  var q = normalizeDigits(raw).trim().toLowerCase().replace(/,/g, "")
  var m = q.match(/^(-?\d+(?:\.\d+)?)\s*(°?[a-z؀-ۿ]+)(?:\s+(?:to|in|الى|إلى)\s+(°?[a-z؀-ۿ]+))?$/)
  if (!m) return null
  var v = parseFloat(m[1]), from = m[2].replace("°", ""), to = (m[3] || "").replace("°", "")
  var temps = { c: true, f: true, k: true, "س": true }
  if (temps[from]) {
    if (from === "س") from = "c"
    if (!to) to = from === "c" ? "f" : "c"
    if (!temps[to]) return null
    var c = from === "c" ? v : from === "f" ? (v - 32) * 5 / 9 : v - 273.15
    var out = to === "c" ? c : to === "f" ? c * 9 / 5 + 32 : c + 273.15
    return { value: out, label: formatNumber(v) + " °" + from.toUpperCase() + " = " + formatNumber(out) + " °" + to.toUpperCase() }
  }
  var g = unitGroup(from)
  if (!g) return null
  if (!to) to = unitDefaults[from] || ""
  if (!to || unitGroup(to) !== g) return null
  var res = v * units[g][from] / units[g][to]
  return { value: res, label: formatNumber(v) + " " + from + " = " + formatNumber(res) + " " + to }
}

// Higher is better; 0 = no match.
function appScore(entry, q) {
  if (!q) return 0
  var name = String(entry.name || "").toLowerCase()
  var generic = String(entry.genericName || "").toLowerCase()
  var keys = (entry.keywords || []).join(" ").toLowerCase()
  var id = String(entry.id || "").toLowerCase()
  if (name === q) return 100
  if (name.indexOf(q) === 0) return 80
  if ((" " + name).indexOf(" " + q) !== -1) return 65
  if (name.indexOf(q) !== -1) return 50
  if (generic.indexOf(q) !== -1) return 35
  if (keys.indexOf(q) !== -1) return 30
  if (id.indexOf(q) !== -1) return 25
  // Subsequence match ("vsc" → "Visual Studio Code")
  var i = 0
  for (var c = 0; c < name.length && i < q.length; c++) if (name.charAt(c) === q.charAt(i)) i++
  return i === q.length ? 10 : 0
}

// Nerd Font glyph for a file by extension.
function fileGlyph(path) {
  var ext = String(path).split(".").pop().toLowerCase()
  if (ext === "pdf") return "󰈦"
  if (/^(png|jpe?g|gif|webp|svg|bmp|heic|avif)$/.test(ext)) return "󰈟"
  if (/^(mp4|mkv|webm|mov|avi)$/.test(ext)) return "󰈫"
  if (/^(mp3|flac|wav|ogg|m4a|opus)$/.test(ext)) return "󰈣"
  if (/^(zip|tar|gz|xz|zst|7z|rar)$/.test(ext)) return "󰀼"
  if (/^(docx?|odt|rtf)$/.test(ext)) return "󰈬"
  if (/^(xlsx?|ods|csv)$/.test(ext)) return "󰈛"
  if (/^(pptx?|odp)$/.test(ext)) return "󰈧"
  if (/^(md|txt|log)$/.test(ext)) return "󰈙"
  if (/^(js|ts|qml|py|sh|lua|json|html|css|rs|go|c|cpp|h|java|kt|rb)$/.test(ext)) return "󰈮"
  return "󰈔"
}
