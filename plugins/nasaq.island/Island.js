// NASAQ: helpers for the Dynamic Island (OSD payloads, prayer times).

// ── OSD: same payload contract as omarchy-osd / omarchy.osd ──────────
function iconFor(name, percent) {
  var n = String(name || "").toLowerCase()
  if (n === "volume-muted" || n === "volume-mute" || n === "muted" || n === "mute") return "󰝟"
  if (n === "volume-low") return "󰕿"
  if (n === "volume-medium") return "󰖀"
  if (n === "volume-high" || n === "volume") return "󰕾"
  if (n === "microphone-muted" || n === "microphone-off" || n === "mic-muted" || n === "mic-off") return "󰍭"
  if (n === "microphone" || n === "mic") return "󰍬"
  if (n === "keyboard") return "󰌌"
  if (n === "brightness" || n === "display") return "󰃠"
  if (n === "touchpad") return "󰟸"
  if (n === "touch" || n === "touchscreen") return "󰝁"
  if (n === "reboot" || n === "restart") return "󰜉"
  if (n === "shutdown" || n === "power" || n === "poweroff") return "󰐥"
  if (n === "logout" || n === "sign-out" || n === "leave") return "󰍃"
  if (n === "media" || n === "player" || n === "media-source" || n === "player-source") return "󰝚"
  if (n === "media-play" || n === "player-play") return "󰐊"
  if (n === "media-pause" || n === "player-pause") return "󰏤"
  if (n === "media-next" || n === "player-next") return "󰒭"
  if (n === "media-previous" || n === "player-previous") return "󰒮"
  if (n.length > 0) return name
  if (percent <= 0) return "󰝟"
  if (percent <= 33) return "󰕿"
  if (percent <= 66) return "󰖀"
  return "󰕾"
}

function osdState(payloadJson) {
  var p = {}
  try { p = JSON.parse(payloadJson || "{}") } catch (e) {}
  var rawValue = p.value === undefined || p.value === null ? "" : String(p.value)
  var rawMessage = String(p.message || "")
  var maxValue = Math.max(1, parseInt(p.max || "100", 10) || 100)
  var parsed = parseInt(rawValue, 10)
  var hasProgress = rawValue !== "" && !isNaN(parsed) && rawMessage === ""
  var value = hasProgress ? Math.max(0, Math.min(maxValue, parsed)) : 0
  var percent = hasProgress ? Math.round(value * 100 / maxValue) : -1
  var duration = parseInt(p.duration === undefined || p.duration === "" ? "1400" : p.duration, 10)
  return {
    icon: iconFor(p.icon || "", percent),
    message: rawMessage || (hasProgress ? (p.progressText || percent + "%") : ""),
    hasProgress: hasProgress,
    fraction: hasProgress ? value / maxValue : 0,
    duration: isNaN(duration) ? 1400 : Math.max(0, duration)
  }
}

// ── Prayer times (Aladhan monthly calendar, Umm al-Qura by default) ──
var prayerKeys = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
var prayerNamesAr = { Fajr: "الفجر", Sunrise: "الشروق", Dhuhr: "الظهر", Asr: "العصر", Maghrib: "المغرب", Isha: "العشاء" }

function pad2(n) { return (n < 10 ? "0" : "") + n }

function gregorianKey(d) {
  return pad2(d.getDate()) + "-" + pad2(d.getMonth() + 1) + "-" + d.getFullYear()
}

function timeOn(day, hhmm) {
  var m = String(hhmm || "").match(/(\d{1,2}):(\d{2})/)
  if (!m) return null
  var t = new Date(day.getFullYear(), day.getMonth(), day.getDate(), parseInt(m[1], 10), parseInt(m[2], 10), 0, 0)
  return t
}

// Returns { prayers: [{key, name, time}], hijri: {day, month, monthEn, year}, tomorrowFajr }
function dayFromMonth(json, day) {
  var data
  try { data = JSON.parse(json) } catch (e) { return null }
  if (!data || !Array.isArray(data.data)) return null
  var key = gregorianKey(day)
  var tomorrow = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1)
  var tkey = gregorianKey(tomorrow)
  var today = null, next = null
  for (var i = 0; i < data.data.length; i++) {
    var entry = data.data[i]
    var g = entry && entry.date && entry.date.gregorian ? entry.date.gregorian.date : ""
    if (g === key) today = entry
    else if (g === tkey) next = entry
  }
  if (!today) return null
  var prayers = []
  for (var k = 0; k < prayerKeys.length; k++) {
    var name = prayerKeys[k]
    prayers.push({ key: name, name: prayerNamesAr[name], time: timeOn(day, today.timings[name]) })
  }
  var h = today.date.hijri || {}
  var tomorrowFajr = next ? timeOn(tomorrow, next.timings.Fajr)
                          : (prayers[0].time ? new Date(prayers[0].time.getTime() + 24 * 3600 * 1000) : null)
  return {
    prayers: prayers,
    hijri: { day: h.day || "", month: h.month ? h.month.ar : "", monthEn: h.month ? h.month.en : "", year: h.year || "" },
    tomorrowFajr: tomorrowFajr
  }
}

// The next prayer after `now`, as { key, name, time, index } (index -1 = tomorrow's Fajr).
function nextPrayer(day, now) {
  if (!day) return null
  for (var i = 0; i < day.prayers.length; i++) {
    var p = day.prayers[i]
    if (p.time && p.time.getTime() > now.getTime()) return { key: p.key, name: p.name, time: p.time, index: i }
  }
  if (day.tomorrowFajr) return { key: "Fajr", name: prayerNamesAr.Fajr, time: day.tomorrowFajr, index: -1 }
  return null
}

function formatTime(d) {
  if (!d) return "--:--"
  var h = d.getHours() % 12
  if (h === 0) h = 12
  return h + ":" + pad2(d.getMinutes())
}

function formatCountdown(ms) {
  var mins = Math.max(0, Math.ceil(ms / 60000))
  if (mins < 60) return mins + "m"
  var h = Math.floor(mins / 60), m = mins % 60
  return h + "h" + (m > 0 ? " " + m + "m" : "")
}

function formatMediaTime(seconds) {
  var s = Math.max(0, Math.floor(seconds || 0))
  return Math.floor(s / 60) + ":" + pad2(s % 60)
}
