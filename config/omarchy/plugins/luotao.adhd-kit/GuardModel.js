// Pure helpers for the hyperfocus guard service. QML loads this with
// `import "GuardModel.js" as Model`; Node loads it with require() for the
// tests under test/.

// The config file is the user's, but a mangled or hostile one must not be
// able to grow the shell: the ignore list is bounded in both directions, and
// an app id is bounded before it is rendered anywhere.
var LIMITS = {
  ignoreEntries: 64,
  ignoreEntry: 64,
  appName: 60
}

var DEFAULTS = {
  enabled: true,
  thresholdMinutes: 90,
  repeatMinutes: 30,
  graceMinutes: 5,
  idleResetMinutes: 10,
  ignore: []
}

function clampInt(value, fallback, min, max) {
  var n = parseInt(value, 10)
  if (!isFinite(n)) return fallback
  return Math.max(min, Math.min(max, n))
}

// Parse the `hyperfocus` section of ~/.config/omarchy/adhd-kit.json.
// Anything missing or mangled falls back to defaults — a broken config file
// should never silently disable the guard or crash the service.
function parseConfig(raw) {
  var section = {}
  try {
    var parsed = JSON.parse(raw || "{}")
    if (parsed && typeof parsed.hyperfocus === "object" && parsed.hyperfocus !== null)
      section = parsed.hyperfocus
  } catch (e) {
    section = {}
  }
  var ignore = []
  if (Array.isArray(section.ignore)) {
    for (var i = 0; i < section.ignore.length && ignore.length < LIMITS.ignoreEntries; i++) {
      var entry = String(section.ignore[i] || "").toLowerCase()
      if (entry.length > LIMITS.ignoreEntry) entry = entry.substring(0, LIMITS.ignoreEntry)
      if (entry) ignore.push(entry)
    }
  }
  return {
    enabled: section.enabled !== false,
    thresholdMinutes: clampInt(section.thresholdMinutes, DEFAULTS.thresholdMinutes, 1, 1440),
    repeatMinutes: clampInt(section.repeatMinutes, DEFAULTS.repeatMinutes, 1, 720),
    graceMinutes: clampInt(section.graceMinutes, DEFAULTS.graceMinutes, 1, 120),
    idleResetMinutes: clampInt(section.idleResetMinutes, DEFAULTS.idleResetMinutes, 1, 240),
    ignore: ignore
  }
}

// "dev.zed.Zed" -> "Zed", "org.mozilla.firefox" -> "Firefox", "Alacritty" ->
// "Alacritty". App ids are reverse-DNS more often than not; the last segment
// is the name humans use.
function friendlyName(appId) {
  var id = String(appId || "")
  if (!id) return "this app"
  var seg = id.split(".").pop()
  var name = seg ? seg.charAt(0).toUpperCase() + seg.slice(1) : id
  return name.length > LIMITS.appName ? name.substring(0, LIMITS.appName) : name
}

// 135 -> "2h 15m", 45 -> "45 minutes"
function formatMinutes(totalMinutes) {
  var m = Math.max(0, Math.round(totalMinutes))
  if (m < 60) return m + (m === 1 ? " minute" : " minutes")
  var h = Math.floor(m / 60)
  var rem = m % 60
  return rem > 0 ? h + "h " + rem + "m" : h + (h === 1 ? " hour" : " hours")
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    LIMITS: LIMITS,
    DEFAULTS: DEFAULTS,
    clampInt: clampInt,
    parseConfig: parseConfig,
    friendlyName: friendlyName,
    formatMinutes: formatMinutes
  }
}
