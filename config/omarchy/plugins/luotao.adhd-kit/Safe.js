// Bounds and plain-text sanitising for everything that reaches this plugin
// from outside it. Three sources are outside the plugin's control:
//
//   * window app ids — every Wayland client picks its own, any length, any
//     bytes; the hyperfocus guard puts one in a notification body
//   * summon payloads — `omarchy-shell shell summon` carries JSON from any
//     local process, so `file` and `fontFamily` arrive attacker-shaped
//   * the state and config files — any local process can grow or garble them
//
// QML loads this with `import "Safe.js" as Safe`; Node loads it with
// require() for the tests under test/.

var LIMITS = {
  label: 120,           // an external string shown to a human
  path: 512,            // a capture path out of a summon payload
  fontFamily: 96,       // a font family name out of a summon payload
  appId: 256,           // a window app id
  payload: 8 * 1024,    // a summon payload
  document: 64 * 1024   // a state or config file this plugin parses
}

// Values that stay data — an app id compared against config, a font family
// handed to Qt: drop the unprintables and bound the length, keep the shape.
function bounded(text, max) {
  var value = String(text === undefined || text === null ? "" : text)
  value = value.replace(/[\u0000-\u001F\u007F]/g, "")
  var limit = typeof max === "number" ? max : LIMITS.label
  return value.length > limit ? value.substring(0, limit) : value
}

// Values that land in a text sink this plugin does not own — a notification
// body (mako and dunst render Pango markup), or a shared component's Text
// (Qt's default textFormat is AutoText, which reads HTML-ish markup and can
// load resources from it). Strip what markup needs, collapse whitespace,
// and ellipsise rather than cut without a mark.
function plainLabel(text, max) {
  var value = String(text === undefined || text === null ? "" : text)
  value = value.replace(/[\u0000-\u001F\u007F]/g, " ")
  value = value.replace(/[<>&]/g, "")
  value = value.replace(/\s+/g, " ").trim()
  var limit = typeof max === "number" ? max : LIMITS.label
  return value.length > limit ? value.substring(0, limit - 1) + "…" : value
}

// A capture target out of a summon payload. Anything over the cap or
// carrying control characters is refused outright so the caller falls back
// to the default inbox — quietly rewriting a path would append the thought
// to a different file than the one that was asked for.
function payloadPath(path, max) {
  var value = String(path === undefined || path === null ? "" : path)
  var limit = typeof max === "number" ? max : LIMITS.path
  if (value === "" || value.length > limit) return ""
  if (/[\u0000-\u001F\u007F]/.test(value)) return ""
  return value
}

// A document this plugin parses (state file, config file, summon payload) is
// refused whole above the cap. These files are small by construction; a
// multi-megabyte one is either broken or hostile, and an empty parse falls
// back to defaults, which is what a broken file should do anyway.
function capDocument(raw, max) {
  var value = String(raw === undefined || raw === null ? "" : raw)
  var limit = typeof max === "number" ? max : LIMITS.document
  return value.length > limit ? "" : value
}

// QML's FileView hands the whole file to the shell before any cap in this
// file could apply, so a local process that grows one of these files would
// grow the long-lived shell with it. Reads therefore go through a helper that
// cannot produce more than the cap: `head -c` bounds what the process writes,
// so the collector on the QML side can never hold more either. One byte over
// the cap is requested on purpose — that is what lets capDocument() tell an
// at-the-limit file from an oversized one and refuse the latter.
function readCommand(path, max) {
  var limit = (typeof max === "number" ? max : LIMITS.document) + 1
  return ["head", "-c", String(limit), "--", String(path === undefined || path === null ? "" : path)]
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    LIMITS: LIMITS,
    bounded: bounded,
    plainLabel: plainLabel,
    payloadPath: payloadPath,
    capDocument: capDocument,
    readCommand: readCommand
  }
}
