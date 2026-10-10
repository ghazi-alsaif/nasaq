// NASAQ: Open-Meteo weather helpers shared by the notification center and the
// desktop widgets. Both read the same cache file the fetch script writes.

// Fetches (at most every 30 min) into ~/.cache/nasaq-island/weather.json and
// prints it. Args: $1 latitude, $2 longitude.
var fetchScript =
  "c=\"${XDG_CACHE_HOME:-$HOME/.cache}/nasaq-island\"; mkdir -p \"$c\"; f=\"$c/weather-$1-$2.json\"; " +
  "if [ ! -s \"$f\" ] || [ $(( $(date +%s) - $(stat -c %Y \"$f\") )) -gt 1800 ]; then " +
  "curl -4 -sf --max-time 10 \"https://api.open-meteo.com/v1/forecast?latitude=$1&longitude=$2" +
  "&current=temperature_2m,weather_code,is_day,relative_humidity_2m,wind_speed_10m" +
  "&daily=temperature_2m_max,temperature_2m_min,weather_code&forecast_days=5&timezone=auto\" -o \"$f.tmp\" " +
  "&& mv \"$f.tmp\" \"$f\"; rm -f \"$f.tmp\"; fi; cat \"$f\" 2>/dev/null"

// WMO weather code → { icon (Nerd Font), label (Arabic) }
function describe(code, isDay) {
  var c = Number(code)
  var day = isDay === undefined ? true : !!isDay
  if (c === 0) return { icon: day ? "󰖙" : "󰖔", label: day ? "Sunny" : "Clear" }
  if (c === 1 || c === 2) return { icon: day ? "󰖕" : "󰼱", label: "Partly cloudy" }
  if (c === 3) return { icon: "󰖐", label: "Cloudy" }
  if (c === 45 || c === 48) return { icon: "󰖑", label: "Fog" }
  if (c >= 51 && c <= 57) return { icon: "󰖗", label: "Drizzle" }
  if (c >= 61 && c <= 67) return { icon: "󰖖", label: "Rain" }
  if (c >= 71 && c <= 77) return { icon: "󰼶", label: "Snow" }
  if (c >= 80 && c <= 82) return { icon: "󰖖", label: "Showers" }
  if (c >= 95) return { icon: "󰙾", label: "Thunderstorms" }
  return { icon: "󰖐", label: "" }
}

function parse(raw) {
  try {
    var d = JSON.parse(raw)
    if (!d || !d.current) return null
    var days = []
    var names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    for (var i = 0; d.daily && i < d.daily.time.length; i++) {
      var dt = new Date(d.daily.time[i] + "T12:00:00")
      days.push({
        name: i === 0 ? "Today" : names[dt.getDay()],
        max: Math.round(d.daily.temperature_2m_max[i]),
        min: Math.round(d.daily.temperature_2m_min[i]),
        icon: describe(d.daily.weather_code[i], true).icon
      })
    }
    var now = describe(d.current.weather_code, d.current.is_day)
    return {
      temp: Math.round(d.current.temperature_2m),
      icon: now.icon,
      label: now.label,
      humidity: Math.round(d.current.relative_humidity_2m || 0),
      wind: Math.round(d.current.wind_speed_10m || 0),
      days: days
    }
  } catch (e) {
    return null
  }
}
