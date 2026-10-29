// Pure helpers for the Obsidian quick note panel. Qt-free so the QML stays
// thin; the vault scan itself is a bash `find` via a Quickshell Process,
// because Quickshell.Io has no directory-listing API.

// Expand ~/ and $HOME/ prefixes; everything else is taken as-is so absolute
// and already-literal paths pass through unchanged.
function expandPath(value, home) {
  var text = String(value === undefined || value === null ? "" : value).trim()
  if (text === "") return ""
  if (text.indexOf("~/") === 0) return home + text.substring(1)
  if (text.indexOf("$HOME/") === 0) return home + text.substring(6)
  return text
}

// Ensure the vault path points to the fleeting root (parent of quicknotes),
// so quicknotes, mnemosyne/inbox, etc. are handled as sibling folders.
function normalizeVaultPath(path) {
  var p = String(path || "").trim()
  if (p === "") return ""
  p = p.replace(/\/+$/, "")
  if (p.lastIndexOf("/quicknotes") === p.length - "/quicknotes".length) {
    p = p.substring(0, p.length - "/quicknotes".length)
  }
  return p
}

// Relative path of `full` inside `vaultPath`; when the file lives outside the
// vault, keep the caller's path untouched (the panel treats a leading "/" as
// an absolute path).
function toRel(vaultPath, full) {
  var v = String(vaultPath || "").replace(/\/+$/, "")
  var f = String(full || "")
  if (v !== "" && f === v) return ""
  var prefix = v + "/"
  if (v !== "" && f.indexOf(prefix) === 0) return f.substring(prefix.length)
  return f
}

function joinPath(vaultPath, rel) {
  var v = String(vaultPath || "").replace(/\/+$/, "")
  var r = String(rel || "")
  if (r === "") return v
  if (r.charAt(0) === "/") return r
  return v === "" ? r : v + "/" + r
}

function getTag(rel) {
  var s = String(rel || "").replace(/^\.\//, "").trim()
  var idx = s.lastIndexOf("/")
  if (idx === -1) return "quicknotes"
  var dir = s.substring(0, idx)
  return dir === "" ? "quicknotes" : dir
}

function getFilename(rel) {
  var s = String(rel || "").trim()
  var idx = s.lastIndexOf("/")
  if (idx === -1) return s
  return s.substring(idx + 1)
}

function getNoteLabel(rel) {
  var fn = getFilename(rel)
  return fn.replace(/\.md$/i, "")
}

function tagLabel(tag) {
  var t = String(tag || "")
  if (t === "all") return "All"
  if (t === "quicknotes") return "quicknotes"
  if (t === "mnemosyne/inbox") return "mnemosyne inbox"
  return t
}

function buildRelPath(tag, filename) {
  var t = String(tag || "").replace(/^\/+|\/+$/g, "").trim()
  var fn = getFilename(filename)
  if (t === "" || t === ".") return fn
  return t + "/" + fn
}

// The scan prints one relative path per line ("find . -type f -name '*.md'").
// Drop the "./" prefix and dot-folders (.obsidian, .trash, .git, ...).
function parseNotes(raw, vaultPath) {
  var out = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var rel = lines[i].replace(/^\s+|\s+$/g, "")
    if (rel === "") continue
    if (rel.indexOf("./") === 0) rel = rel.substring(2)
    if (rel === "") continue
    var top = rel.split("/")[0]
    if (top.length > 0 && top.charAt(0) === ".") continue
    out.push({
      rel: rel,
      label: getNoteLabel(rel),
      filename: getFilename(rel),
      tag: getTag(rel),
      path: joinPath(vaultPath, rel)
    })
  }
  return out
}

function getAvailableTags(notes) {
  var defaults = ["quicknotes", "mnemosyne/inbox"]
  var seen = {}
  var out = []
  for (var i = 0; i < defaults.length; i++) {
    seen[defaults[i]] = true
    out.push(defaults[i])
  }
  for (var j = 0; j < (notes || []).length; j++) {
    var t = notes[j].tag
    if (t && !seen[t]) {
      seen[t] = true
      out.push(t)
    }
  }
  return out
}

// Case-insensitive substring match against the note label, tag, or rel path.
// If activeTag is not "all", filter by tag.
function filterNotes(notes, query, activeTag) {
  var q = String(query || "").toLowerCase().trim()
  var tag = String(activeTag || "all").trim()
  var out = []
  for (var i = 0; i < (notes || []).length; i++) {
    var item = notes[i]
    if (tag !== "" && tag !== "all" && item.tag !== tag) {
      continue
    }
    if (q === "") {
      out.push(item)
    } else {
      var matchLabel = item.label.toLowerCase().indexOf(q) !== -1
      var matchTag = item.tag.toLowerCase().indexOf(q) !== -1
      var matchRel = item.rel.toLowerCase().indexOf(q) !== -1
      if (matchLabel || matchTag || matchRel) {
        out.push(item)
      }
    }
  }
  return out
}

// lines like "/home/user/Documents/notes/.obsidian" -> "/home/user/Documents/notes".
// Sort keeps the most predictable candidate (Documents first) at the front.
function parseVaultCandidates(raw) {
  var seen = {}
  var out = []
  var lines = String(raw || "").split("\n")
  var marker = "/.obsidian"
  for (var i = 0; i < lines.length; i++) {
    var p = lines[i].replace(/^\s+|\s+$/g, "")
    if (p === "") continue
    if (p.lastIndexOf(marker) === p.length - marker.length)
      p = p.substring(0, p.length - marker.length)
    p = p.replace(/\/+$/, "")
    if (p === "" || seen[p]) continue
    seen[p] = true
    out.push(p)
  }
  return out
}

function getDirectory(path) {
  var s = String(path || "")
  var idx = s.lastIndexOf("/")
  if (idx === -1) return ""
  return s.substring(0, idx)
}

if (typeof module !== "undefined") {
  module.exports = {
    expandPath: expandPath,
    normalizeVaultPath: normalizeVaultPath,
    toRel: toRel,
    joinPath: joinPath,
    getTag: getTag,
    getFilename: getFilename,
    getNoteLabel: getNoteLabel,
    tagLabel: tagLabel,
    buildRelPath: buildRelPath,
    parseNotes: parseNotes,
    getAvailableTags: getAvailableTags,
    filterNotes: filterNotes,
    parseVaultCandidates: parseVaultCandidates,
    getDirectory: getDirectory
  }
}
