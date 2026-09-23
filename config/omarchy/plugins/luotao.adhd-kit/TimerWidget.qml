import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TimerModel.js" as Model
import "Safe.js" as Safe

// Time Timer-style visual countdown for the bar: a disc whose filled sector
// is the time left, next to an mm:ss label. Built for time blindness — the
// point is that remaining time is visible as a shrinking shape, not a number
// you have to parse.
//
// Left click opens the control panel, right click pauses/resumes, middle
// click cancels, scrolling nudges a running timer by a minute.
Panel {
  id: root
  moduleName: "luotao.adhd-kit"
  ipcTarget: "luotao.adhd-kit"
  manageIpc: false

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)

  // ---- Shared state. The bar exists once per monitor, so the source of
  //      truth is a state file every instance watches; it also lets a timer
  //      survive shell restarts. Instances apply actions locally first so
  //      the click feels instant, then persist for their peers.
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/adhd-kit/timer.json"

  property double endAt: 0            // epoch ms; > 0 while running
  property int durationSec: 0         // full span of the current timer
  property int pausedRemainingSec: 0  // > 0 while paused
  property double nowMs: Date.now()

  readonly property bool running: endAt > 0
  readonly property bool paused: !running && pausedRemainingSec > 0
  readonly property bool idle: !running && !paused
  readonly property int remaining: running
    ? Math.max(0, Math.round((endAt - nowMs) / 1000))
    : (paused ? pausedRemainingSec : 0)
  readonly property real frac: durationSec > 0 && !idle
    ? Math.max(0, Math.min(1, remaining / durationSec)) : 0
  readonly property bool closing: running && remaining <= 60 && remaining > 0

  readonly property var presets: Model.parsePresets(setting("presets", "5,15,25,45"))
  readonly property bool showLabel: setting("showLabel", true) === true

  property string customMinutes: ""

  // ---- Actions

  function startTimer(minutes) {
    var m = parseInt(minutes, 10)
    if (!isFinite(m) || m <= 0) return
    m = Math.min(m, 999)
    nowMs = Date.now()
    durationSec = m * 60
    pausedRemainingSec = 0
    endAt = nowMs + durationSec * 1000
    customMinutes = ""
    persist()
  }

  function pauseTimer() {
    if (!running) return
    var r = remaining
    endAt = 0
    pausedRemainingSec = Math.max(1, r)
    persist()
  }

  function resumeTimer() {
    if (!paused) return
    nowMs = Date.now()
    endAt = nowMs + pausedRemainingSec * 1000
    pausedRemainingSec = 0
    persist()
  }

  function togglePause() {
    if (running) pauseTimer()
    else if (paused) resumeTimer()
  }

  function cancelTimer() {
    endAt = 0
    pausedRemainingSec = 0
    durationSec = 0
    persist()
  }

  // Nudge the live timer by whole minutes; the total grows with it so the
  // disc fraction keeps meaning "share of what I committed to".
  function adjustTimer(deltaMinutes) {
    var deltaSec = Math.round(deltaMinutes * 60)
    if (running) {
      var r = remaining + deltaSec
      if (r <= 0) { finish(); return }
      nowMs = Date.now()
      endAt = nowMs + r * 1000
      durationSec = Math.max(durationSec + deltaSec, r)
      persist()
    } else if (paused) {
      var p = pausedRemainingSec + deltaSec
      if (p <= 0) { cancelTimer(); return }
      pausedRemainingSec = p
      durationSec = Math.max(durationSec + deltaSec, p)
      persist()
    }
  }

  function finish() {
    var mins = Math.max(1, Math.round(durationSec / 60))
    endAt = 0
    pausedRemainingSec = 0
    durationSec = 0
    if (isLeader()) {
      persist()
      Quickshell.execDetached([
        root.omarchyPath + "/bin/omarchy-notification-send",
        "Time's up",
        mins + (mins === 1 ? " minute" : " minutes") + " — done. Stand up, stretch, decide what's next."
      ])
    }
  }

  // One bar surface per monitor means one timer tick per monitor; the first
  // live instance speaks for the group so a finished timer notifies once.
  function isLeader() {
    if (!bar || typeof bar.moduleWidgets !== "function") return true
    var items = bar.moduleWidgets(moduleName)
    return !items || items.length === 0 || items[0] === root
  }

  function persist() {
    Quickshell.execDetached(Model.persistCommand(statePath, endAt, durationSec, pausedRemainingSec))
  }

  // The state file is this plugin's, but any local process can grow or
  // garble it; an oversized document is refused before it is parsed.
  function applyState(raw) {
    var s = Model.parseState(Safe.capDocument(raw), Date.now())
    endAt = s.endAt
    durationSec = s.durationSec
    pausedRemainingSec = s.pausedRemainingSec
    nowMs = Date.now()
  }

  function startCustom() {
    if (customMinutes !== "") startTimer(customMinutes)
  }

  readonly property string statusText: running
    ? Model.formatRemaining(remaining) + " left"
    : paused ? "Paused at " + Model.formatRemaining(remaining)
    : "No timer running"

  readonly property string barTooltip: idle
    ? "Visual timer — click to start"
    : statusText + " · right-click " + (running ? "pause" : "resume") + " · scroll ±1m"

  onOpenedChanged: if (opened) {
    reloadState()
    customMinutes = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // The state file is the bus between surfaces: this bar instance, the bars on
  // other monitors, the big-timer overlay, and scripts. It is read through a
  // bounded helper rather than FileView, because FileView would hand the whole
  // file to the shell before any cap could apply — see Safe.readCommand. The
  // FileView below stays only as a change notifier and never retains content.
  Process {
    id: stateReader
    command: Safe.readCommand(root.statePath, Safe.LIMITS.document)
    stdout: StdioCollector { onStreamFinished: root.applyState(this.text) }
    // A missing state file is the normal idle case, not something to log.
    stderr: StdioCollector {}
  }

  function reloadState() {
    stateReader.running = false
    stateReader.running = true
  }

  FileView {
    path: root.statePath
    watchChanges: true
    // preload:false and blockAllReads together are what keep this a pure
    // notifier: without preload:false the view reads the file in full the
    // moment the path is assigned, before blockAllReads reaches the C++ side,
    // so a shell started with an already-huge file would still retain it.
    preload: false
    blockAllReads: true
    printErrors: false
    onFileChanged: root.reloadState()
  }

  // A watch established for a file that does not exist yet never fires, so
  // read once on startup and whenever the panel opens.
  Component.onCompleted: root.reloadState()

  Timer {
    interval: 1000
    running: root.running
    repeat: true
    onTriggered: {
      root.nowMs = Date.now()
      if (root.remaining <= 0) root.finish()
    }
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function start(minutes: string): string {
      var m = parseInt(minutes, 10)
      if (!isFinite(m) || m <= 0) return "expected minutes, e.g. `start 25`"
      root.startTimer(m)
      return "ok"
    }
    function pause(): string { root.pauseTimer(); return "ok" }
    function resume(): string { root.resumeTimer(); return "ok" }
    function cancel(): string { root.cancelTimer(); return "ok" }
    function status(): string {
      return JSON.stringify({
        state: root.running ? "running" : root.paused ? "paused" : "idle",
        remainingSec: root.remaining,
        durationSec: root.durationSec
      })
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    tooltipText: root.barTooltip
    fixedWidth: root.vertical ? -1 : content.implicitWidth + button.scaledHorizontalMargin * 2

    onPressed: function(b) {
      if (b === Qt.RightButton) root.togglePause()
      else if (b === Qt.MiddleButton) root.cancelTimer()
      else root.toggle()
    }
    onWheelMoved: function(delta) {
      if (!root.idle) root.adjustTimer(delta > 0 ? 1 : -1)
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(6)

      // Sub-minute urgency reads as a pulse rather than a color swap alone —
      // peripheral vision catches motion long before it catches hue.
      opacity: root.closing ? pulse.opacityValue : 1

      Canvas {
        id: disc
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(Style.space(12), Math.round(Style.bar.iconSlot * 0.55))
        height: width

        readonly property real fracNow: root.frac
        readonly property bool idleNow: root.idle
        readonly property color fillColor: root.paused ? root.dim
          : root.closing ? Color.urgent : Color.accent
        readonly property color ringColor: root.idle ? root.foreground : root.dim

        onFracNowChanged: requestPaint()
        onIdleNowChanged: requestPaint()
        onFillColorChanged: requestPaint()
        onRingColorChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()

        onPaint: {
          var c = width / 2
          var r = c - 1
          if (r <= 0) return
          var ctx = getContext("2d")
          ctx.reset()

          ctx.strokeStyle = ringColor
          ctx.lineWidth = 1
          ctx.globalAlpha = idleNow ? 0.8 : 0.5
          ctx.beginPath()
          ctx.arc(c, c, r, 0, Math.PI * 2, false)
          ctx.stroke()
          ctx.globalAlpha = 1

          if (idleNow) {
            ctx.fillStyle = ringColor
            ctx.globalAlpha = 0.8
            ctx.beginPath()
            ctx.arc(c, c, Math.max(1, r * 0.18), 0, Math.PI * 2, false)
            ctx.fill()
            ctx.globalAlpha = 1
            return
          }

          // Remaining time as a filled sector from 12 o'clock, clockwise —
          // the Time Timer disc.
          ctx.fillStyle = fillColor
          ctx.beginPath()
          ctx.moveTo(c, c)
          ctx.arc(c, c, r - 1, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * fracNow, false)
          ctx.closePath()
          ctx.fill()
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.vertical && root.showLabel && !root.idle
        text: Model.formatRemaining(root.remaining)
        textFormat: Text.PlainText
        color: root.paused ? root.dim
          : root.closing ? Color.urgent : (root.bar ? root.bar.barForeground : root.foreground)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
      }
    }

    SequentialAnimation {
      id: pulse
      property real opacityValue: 1
      running: root.closing
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { target: pulse; property: "opacityValue"; from: 1; to: 0.35; duration: 500; easing.type: Easing.InOutSine }
      NumberAnimation { target: pulse; property: "opacityValue"; from: 0.35; to: 1; duration: 500; easing.type: Easing.InOutSine }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(420))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onReturnRequested: root.startCustom()
      onDeleteRequested: if (root.customMinutes !== "")
        root.customMinutes = root.customMinutes.slice(0, -1)
      onTextKey: function(text) {
        var key = String(text || "")
        if (root.idle && /^[0-9]$/.test(key)) {
          if (root.customMinutes.length < 3) root.customMinutes += key
          return
        }
        var k = key.toLowerCase()
        if (k === " ") root.togglePause()
        else if (k === "c" || k === "x") root.cancelTimer()
        else if (k === "+" || k === "=") root.adjustTimer(5)
        else if (k === "-") root.adjustTimer(-5)
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "Visual Timer"
          meta: root.statusText
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Canvas {
              width: Style.font.display
              height: Style.font.display
              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var c = width / 2
                ctx.strokeStyle = root.foreground
                ctx.lineWidth = 1.5
                ctx.beginPath()
                ctx.arc(c, c, c - 1.5, 0, Math.PI * 2, false)
                ctx.stroke()
                ctx.fillStyle = root.foreground
                ctx.beginPath()
                ctx.moveTo(c, c)
                ctx.arc(c, c, c - 3.5, -Math.PI / 2, Math.PI * 0.4, false)
                ctx.closePath()
                ctx.fill()
              }
            }
          }
        }

        // ---- Idle: pick a duration.
        Column {
          visible: root.idle
          width: parent.width
          spacing: Style.space(10)

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.presets

              Button {
                required property int modelData
                text: modelData + "m"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: {
                  root.startTimer(modelData)
                  root.close()
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: root.customMinutes !== ""
            text: "Custom: " + root.customMinutes + " min — press Enter to start"
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: root.customMinutes === ""
              ? "Click a preset, or type minutes and press Enter."
              : "Backspace edits · Esc closes"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }

        // ---- Running / paused: the big number and the controls.
        Column {
          visible: !root.idle
          width: parent.width
          spacing: Style.space(10)

          Text {
            width: parent.width
            text: Model.formatRemaining(root.remaining)
            textFormat: Text.PlainText
            color: root.closing ? Color.urgent : root.foreground
            opacity: root.paused ? 0.55 : 1
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            horizontalAlignment: Text.AlignHCenter
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Button {
              text: root.running ? "Pause" : "Resume"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.togglePause()
            }
            Button {
              text: "+5m"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.adjustTimer(5)
            }
            Button {
              text: "−5m"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.adjustTimer(-5)
            }
            Button {
              text: "Cancel"
              bordered: true
              foreground: Color.urgent
              fontFamily: root.fontFamily
              onClicked: {
                root.cancelTimer()
                root.close()
              }
            }
          }

          Text {
            width: parent.width
            text: "Space pause · +/− adjust 5m · C cancel · Esc close"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
