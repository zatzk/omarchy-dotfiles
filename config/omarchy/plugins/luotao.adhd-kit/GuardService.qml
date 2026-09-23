import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "GuardModel.js" as Model
import "Safe.js" as Safe

// Hyperfocus guard: notices when one app has held focus for hours and asks,
// gently, whether that is still on purpose. ADHD hyperfocus feels great and
// costs meals, water, posture, and whole afternoons — the guard is not a
// blocker, just a hand on the shoulder at a configurable interval.
//
// A streak is wall-clock time since an app took focus. Brief detours to
// other windows (up to graceMinutes) neither reset nor pause it — checking
// a browser tab mid-hyperfocus is still hyperfocus. Staying away past the
// grace adopts the new app; going idle (away from keyboard) resets outright.
//
// Config lives in ~/.config/omarchy/adhd-kit.json under "hyperfocus":
//   { "hyperfocus": { "thresholdMinutes": 90, "repeatMinutes": 30,
//     "graceMinutes": 5, "idleResetMinutes": 10,
//     "ignore": ["mpv"], "enabled": true } }
Item {
  id: root

  // Injected by omarchy-shell's service loader (which also assigns
  // omarchyPath — keep it writable).
  property var shell: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/adhd-kit.json"

  property var config: Model.parseConfig("")

  readonly property var toplevel: ToplevelManager.activeToplevel
  // Any Wayland client picks its own app id, so it is external input: bound
  // it on the way in, before it is compared, stored or rendered.
  readonly property string activeApp: toplevel && toplevel.appId
    ? Safe.bounded(toplevel.appId, Safe.LIMITS.appId) : ""

  property string streakApp: ""
  property double streakStartMs: 0
  property double awaySinceMs: 0
  property double focusedSinceMs: 0
  property int notifiedUpToMin: 0
  property double snoozeUntilMs: 0

  readonly property int streakMinutes: streakApp !== "" && streakStartMs > 0
    ? Math.floor((Date.now() - streakStartMs) / 60000) : 0

  function isIgnored(app) {
    return config.ignore.indexOf(String(app).toLowerCase()) !== -1
  }

  function resetStreak() {
    streakApp = ""
    streakStartMs = 0
    awaySinceMs = 0
    notifiedUpToMin = 0
  }

  function adopt(app, sinceMs) {
    streakApp = app
    streakStartMs = sinceMs > 0 ? sinceMs : Date.now()
    awaySinceMs = 0
    notifiedUpToMin = 0
  }

  function evaluate() {
    if (!config.enabled) return
    var now = Date.now()
    var app = activeApp

    if (app === "" || isIgnored(app)) {
      // Nothing focused (or something we don't count): the streak survives
      // the grace window, same as any other detour.
      if (streakApp !== "" && awaySinceMs === 0) awaySinceMs = now
      if (streakApp !== "" && now - awaySinceMs >= config.graceMinutes * 60000) resetStreak()
      return
    }

    if (streakApp === "") {
      adopt(app, focusedSinceMs)
      return
    }

    if (app === streakApp) {
      awaySinceMs = 0
      maybeNotify(now)
      return
    }

    if (awaySinceMs === 0) awaySinceMs = now
    if (now - awaySinceMs >= config.graceMinutes * 60000)
      adopt(app, focusedSinceMs)
  }

  function maybeNotify(now) {
    if (now < snoozeUntilMs) return
    var min = Math.floor((now - streakStartMs) / 60000)
    if (min < config.thresholdMinutes) return
    if (notifiedUpToMin !== 0 && min < notifiedUpToMin + config.repeatMinutes) return
    notifiedUpToMin = min
    Quickshell.execDetached([
      root.omarchyPath + "/bin/omarchy-notification-send",
      "Hyperfocus check",
      Model.formatMinutes(min) + " in " + Safe.plainLabel(Model.friendlyName(streakApp))
        + " — stand up, stretch, sip some water. Still on purpose?"
    ])
  }

  onActiveAppChanged: {
    focusedSinceMs = Date.now()
    evaluate()
  }

  onConfigChanged: if (!config.enabled) resetStreak()

  // Away from keyboard long enough means the hyperfocus broke on its own;
  // whatever window happens to hold focus is not a streak.
  IdleMonitor {
    enabled: root.config.enabled
    timeout: root.config.idleResetMinutes * 60
    respectInhibitors: false
    onIsIdleChanged: if (isIdle) root.resetStreak()
  }

  Timer {
    interval: 30000
    running: root.config.enabled
    repeat: true
    onTriggered: root.evaluate()
  }

  // Read through a bounded helper rather than FileView, which would hand the
  // whole file to the long-lived shell before any cap could apply (see
  // Safe.readCommand). A missing config reads as empty, which is the same as
  // a broken one: defaults. The FileView is only a change notifier.
  Process {
    id: configReader
    command: Safe.readCommand(root.configPath, Safe.LIMITS.document)
    stdout: StdioCollector {
      onStreamFinished: root.config = Model.parseConfig(Safe.capDocument(this.text))
    }
    stderr: StdioCollector {}
  }

  function reloadConfig() {
    configReader.running = false
    configReader.running = true
  }

  FileView {
    path: root.configPath
    watchChanges: true
    // preload:false and blockAllReads together are what keep this a pure
    // notifier: without preload:false the view reads the file in full the
    // moment the path is assigned, before blockAllReads reaches the C++ side,
    // so a shell started with an already-huge file would still retain it.
    preload: false
    blockAllReads: true
    printErrors: false
    onFileChanged: root.reloadConfig()
  }

  IpcHandler {
    target: "luotao.adhd-kit.guard"

    function status(): string {
      return JSON.stringify({
        enabled: root.config.enabled,
        app: root.streakApp,
        streakMinutes: root.streakMinutes,
        thresholdMinutes: root.config.thresholdMinutes,
        notifiedUpToMin: root.notifiedUpToMin,
        snoozedUntil: root.snoozeUntilMs,
        activeApp: root.activeApp
      })
    }
    function reset(): string { root.resetStreak(); return "ok" }
    function snooze(minutes: string): string {
      var m = parseInt(minutes, 10)
      if (!isFinite(m) || m <= 0) m = 30
      root.snoozeUntilMs = Date.now() + m * 60000
      return "snoozed " + m + "m"
    }
  }

  Component.onCompleted: {
    console.log("adhd-kit: hyperfocus guard ready")
    reloadConfig()
    focusedSinceMs = Date.now()
    evaluate()
  }
}
