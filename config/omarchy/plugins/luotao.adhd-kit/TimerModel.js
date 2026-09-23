// Pure helpers for the visual timer. No Qt imports so everything here is
// trivially testable and shareable between the widget and future surfaces.
// QML loads this with `import "TimerModel.js" as Model`; Node loads it with
// require() for the tests under test/.

var DEFAULT_PRESETS = [5, 15, 25, 45]

// "5,15,25,45" -> [5, 15, 25, 45]; junk entries dropped, empty input falls
// back to the defaults so a mangled shell.json never leaves the panel blank.
function parsePresets(raw) {
  var parts = String(raw === undefined || raw === null ? "" : raw).split(",")
  var out = []
  for (var i = 0; i < parts.length; i++) {
    var n = parseInt(parts[i].trim(), 10)
    if (isFinite(n) && n >= 1 && n <= 999 && out.indexOf(n) === -1) out.push(n)
  }
  return out.length ? out.slice(0, 6) : DEFAULT_PRESETS.slice()
}

// Argv for persisting timer state, shared by every surface that writes it
// (bar widget, big-timer overlay). Values travel as positional args so the
// JSON payload is data to the shell, never syntax.
function persistCommand(statePath, endAt, durationSec, pausedRemainingSec) {
  var payload = JSON.stringify({
    endAt: endAt,
    durationSec: durationSec,
    pausedRemainingSec: pausedRemainingSec,
    updatedAt: Date.now()
  })
  return [
    "sh", "-c",
    'mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1"',
    "sh", statePath, payload
  ]
}

function pad(n) {
  return (n < 10 ? "0" : "") + n
}

// 1500 -> "25:00", 3725 -> "1:02:05"
function formatRemaining(totalSecs) {
  var s = Math.max(0, Math.round(totalSecs))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var sec = s % 60
  return h > 0 ? h + ":" + pad(m) + ":" + pad(sec) : m + ":" + pad(sec)
}

// Parse the persisted state file. A timer that expired while the shell was
// down comes back as idle — the moment passed; a stale "Time's up" at login
// is noise, not help.
function parseState(raw, nowMs) {
  var s
  try {
    s = JSON.parse(raw || "{}")
  } catch (e) {
    s = {}
  }
  var endAt = Number(s.endAt) || 0
  var durationSec = Math.max(0, Math.round(Number(s.durationSec) || 0))
  var pausedRemainingSec = Math.max(0, Math.round(Number(s.pausedRemainingSec) || 0))
  if (endAt > 0 && endAt <= nowMs) {
    endAt = 0
    pausedRemainingSec = 0
  }
  return { endAt: endAt, durationSec: durationSec, pausedRemainingSec: pausedRemainingSec }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    DEFAULT_PRESETS: DEFAULT_PRESETS,
    parsePresets: parsePresets,
    persistCommand: persistCommand,
    formatRemaining: formatRemaining,
    parseState: parseState
  }
}
