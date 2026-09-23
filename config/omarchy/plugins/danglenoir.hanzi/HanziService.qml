import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: service

  property bool loading: false
  property bool refreshQueued: false
  property bool queuedShuffle: false
  property bool receivedOutput: false
  property var snapshot: ({
    ok: false,
    stale: false,
    error: "Loading today's hanzi...",
    errorCode: "loading"
  })

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || (home + "/.cache")
  readonly property string cacheDir: cacheHome + "/omarchy-hanzi"
  readonly property string pluginDir: decodeURIComponent(
    Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, ""))
  readonly property string scriptPath: pluginDir + "/Hanzi.js"
  readonly property bool available: snapshot && snapshot.ok === true

  signal updated()

  property bool _refreshPending: false
  property bool _pendingShuffle: false

  function queueRefresh(shuffle) {
    _pendingShuffle = _pendingShuffle || shuffle === true
    if (!_refreshPending) {
      _refreshPending = true
      Qt.callLater(function() {
        _refreshPending = false
        var doShuffle = _pendingShuffle
        _pendingShuffle = false
        service.refresh(doShuffle)
      })
    }
  }

  function refresh(shuffle) {
    if (poll.running) {
      refreshQueued = true
      queuedShuffle = queuedShuffle || shuffle === true
      return
    }

    var command = ["node", service.scriptPath, "--cache", service.cacheDir]
    if (shuffle === true) command.push("--shuffle")
    receivedOutput = false
    loading = true
    poll.command = command
    poll.running = true
  }

  function sanitizeText(value) {
    var text = String(value == null ? "" : value)
    text = text.replace(/<[^>]*>/g, "").replace(/[<>]/g, "")
    text = text.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "")
    text = text.replace(/[\u202A-\u202E\u2066-\u2069]/g, "")
    if (text.length > 200)
      text = text.substring(0, 200)
    return text
  }

  function sanitizeField(obj, key) {
    if (!obj || obj[key] === undefined || obj[key] === null)
      return
    obj[key] = sanitizeText(obj[key])
  }

  function sanitizeList(list, keys) {
    if (!Array.isArray(list))
      return
    for (var i = 0; i < list.length; i++) {
      if (!list[i] || typeof list[i] !== "object")
        continue
      for (var k = 0; k < keys.length; k++)
        sanitizeField(list[i], keys[k])
    }
  }

  function sanitizeSnapshot(data) {
    if (!data || typeof data !== "object")
      return data
    var keys = [
      "error", "errorCode", "date", "character", "traditional", "pinyin",
      "meaning", "hskLevel", "hskLabel", "etymology", "radical", "dictionaryUrl"
    ]
    for (var i = 0; i < keys.length; i++)
      sanitizeField(data, keys[i])
    sanitizeList(data.components, ["character", "pinyin", "meaning"])
    sanitizeList(data.words, ["word", "pinyin", "meaning"])
    return data
  }

  function consume(raw) {
    receivedOutput = true
    loading = false
    var text = String(raw || "").trim()
    if (text === "") {
      snapshot = {
        ok: false,
        stale: false,
        error: "The hanzi helper returned no output.",
        errorCode: "empty_response"
      }
      updated()
      return
    }

    try {
      var parsed = JSON.parse(text)
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
        throw new Error("invalid snapshot")
      snapshot = sanitizeSnapshot(parsed)
    } catch (error) {
      snapshot = {
        ok: false,
        stale: false,
        error: "The hanzi helper returned unreadable output.",
        errorCode: "invalid_response"
      }
    }
    updated()
  }

  function finishPoll() {
    loading = false
    if (!receivedOutput) consume("")
    if (!refreshQueued) return

    var shuffle = queuedShuffle
    refreshQueued = false
    queuedShuffle = false
    Qt.callLater(function() { service.refresh(shuffle) })
  }

  Component.onCompleted: service.queueRefresh(false)

  Process {
    id: poll
    running: false

    stdout: StdioCollector {
      id: stdoutCollector
      waitForEnd: true
      onStreamFinished: service.consume(stdoutCollector.text)
    }

    onExited: Qt.callLater(service.finishPoll)
  }

  Timer {
    interval: 30 * 60 * 1000
    running: true
    repeat: true
    onTriggered: service.refresh(false)
  }
}
