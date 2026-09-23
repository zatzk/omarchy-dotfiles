import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "../TimerModel.js" as Model
import "../Safe.js" as Safe

// Fullscreen Time Timer: the same shared timer as the bar widget, drawn big
// enough to read from across the room. Glanceability is the feature — no
// window to find, no app to foreground, the wall clock version of the bar
// disc.
//
// It speaks the same state-file protocol as the bar widget, so starting,
// pausing or nudging here shows up on every monitor's bar instantly (and
// vice versa). Finish notifications stay with the bar widget — this view
// only ever mirrors.
Item {
  id: root

  signal dismissRequested()

  property bool opened: false
  property string fontFamily: Style.font.menuFamily

  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/adhd-kit/timer.json"

  property double endAt: 0
  property int durationSec: 0
  property int pausedRemainingSec: 0
  property double nowMs: Date.now()
  property string customMinutes: ""
  readonly property var presets: Model.parsePresets("5,15,25,45")

  readonly property bool running: endAt > 0
  readonly property bool paused: !running && pausedRemainingSec > 0
  readonly property bool idle: !running && !paused
  readonly property int remaining: running
    ? Math.max(0, Math.round((endAt - nowMs) / 1000))
    : (paused ? pausedRemainingSec : 0)
  readonly property real frac: durationSec > 0 && !idle
    ? Math.max(0, Math.min(1, remaining / durationSec)) : 0
  readonly property bool closing: running && remaining <= 60 && remaining > 0

  property color foreground: Color.menu.text
  property color scrim: Color.menu.scrim
  readonly property color dim: Qt.darker(foreground, 1.55)

  function openView(payload) {
    // The summon payload comes from any local process: bound what it carries.
    var family = Safe.bounded(payload.fontFamily, Safe.LIMITS.fontFamily)
    if (family) root.fontFamily = family
    root.customMinutes = ""
    root.nowMs = Date.now()
    root.opened = true
    root.reloadState()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    root.dismissRequested()
  }

  // ---- Same action set as the bar widget, same persistence protocol.

  function persist() {
    Quickshell.execDetached(Model.persistCommand(statePath, endAt, durationSec, pausedRemainingSec))
  }

  function reloadState() {
    stateReader.running = false
    stateReader.running = true
  }

  function applyState(raw) {
    var s = Model.parseState(Safe.capDocument(raw), Date.now())
    endAt = s.endAt
    durationSec = s.durationSec
    pausedRemainingSec = s.pausedRemainingSec
    nowMs = Date.now()
  }

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

  function togglePause() {
    if (running) {
      var r = remaining
      endAt = 0
      pausedRemainingSec = Math.max(1, r)
      persist()
    } else if (paused) {
      nowMs = Date.now()
      endAt = nowMs + pausedRemainingSec * 1000
      pausedRemainingSec = 0
      persist()
    }
  }

  function cancelTimer() {
    endAt = 0
    pausedRemainingSec = 0
    durationSec = 0
    persist()
  }

  function adjustTimer(deltaMinutes) {
    var deltaSec = Math.round(deltaMinutes * 60)
    if (running) {
      var r = remaining + deltaSec
      if (r <= 0) { cancelTimer(); return }
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

  readonly property string statusText: running
    ? (closing ? "Almost there" : "Focus")
    : paused ? "Paused"
    : "How long do you have?"

  // Read through a bounded helper, not FileView: FileView would hand the whole
  // file to the shell before any cap could apply (see Safe.readCommand). The
  // FileView is only a change notifier and never retains content.
  Process {
    id: stateReader
    command: Safe.readCommand(root.statePath, Safe.LIMITS.document)
    stdout: StdioCollector { onStreamFinished: root.applyState(this.text) }
    stderr: StdioCollector {}
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

  // Display tick only while visible and running. On expiry the view goes
  // quiet locally; the bar widget owns the finish (notification + persisted
  // reset) and this view mirrors it through the state file.
  Timer {
    interval: 1000
    running: root.opened && root.running
    repeat: true
    onTriggered: {
      root.nowMs = Date.now()
      if (root.remaining <= 0) {
        root.endAt = 0
        root.pausedRemainingSec = 0
        root.durationSec = 0
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "adhd-kit-bigtimer"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    readonly property real discSize: Math.min(width, height) * 0.46

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    // A second, near-opaque pass: the menu scrim is tuned to keep a menu's
    // surroundings readable, but the big timer wants the desktop gone — both
    // for focus and because glanceable means high contrast.
    Rectangle {
      anchors.fill: parent
      color: Color.menu.background
      opacity: 0.92
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.dismiss()
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (root.idle && root.customMinutes !== "") root.startTimer(root.customMinutes)
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Backspace) {
          root.customMinutes = root.customMinutes.slice(0, -1)
          event.accepted = true
          return
        }
        var t = event.text || ""
        if (root.idle && /^[0-9]$/.test(t)) {
          if (root.customMinutes.length < 3) root.customMinutes += t
          event.accepted = true
        } else if (t === " ") {
          root.togglePause()
          event.accepted = true
        } else if (t === "c" || t === "x") {
          root.cancelTimer()
          event.accepted = true
        } else if (t === "+" || t === "=") {
          root.adjustTimer(5)
          event.accepted = true
        } else if (t === "-") {
          root.adjustTimer(-5)
          event.accepted = true
        }
      }
    }

    Column {
      anchors.centerIn: parent
      spacing: Style.space(24)
      opacity: root.closing ? pulse.opacityValue : 1

      Canvas {
        id: disc
        anchors.horizontalCenter: parent.horizontalCenter
        width: panel.discSize
        height: panel.discSize

        readonly property real fracNow: root.frac
        readonly property bool idleNow: root.idle
        readonly property color fillColor: root.paused ? root.dim
          : root.closing ? Color.urgent : Color.accent
        readonly property color ringColor: root.dim

        onFracNowChanged: requestPaint()
        onIdleNowChanged: requestPaint()
        onFillColorChanged: requestPaint()
        onWidthChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()

        onPaint: {
          var c = width / 2
          var r = c - 4
          // First paint can land before the layer surface has a size;
          // ctx.arc throws on a negative radius.
          if (r <= 0) return
          var ctx = getContext("2d")
          ctx.reset()

          ctx.strokeStyle = ringColor
          ctx.lineWidth = 2
          ctx.globalAlpha = 0.6
          ctx.beginPath()
          ctx.arc(c, c, r, 0, Math.PI * 2, false)
          ctx.stroke()

          // Minute graduations, like the physical clock face.
          var ticks = 12
          for (var i = 0; i < ticks; i++) {
            var a = (Math.PI * 2 * i) / ticks - Math.PI / 2
            ctx.beginPath()
            ctx.moveTo(c + Math.cos(a) * (r - 10), c + Math.sin(a) * (r - 10))
            ctx.lineTo(c + Math.cos(a) * (r - 2), c + Math.sin(a) * (r - 2))
            ctx.stroke()
          }
          ctx.globalAlpha = 1

          if (idleNow) return

          ctx.fillStyle = fillColor
          ctx.globalAlpha = 0.9
          ctx.beginPath()
          ctx.moveTo(c, c)
          ctx.arc(c, c, r - 14, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * fracNow, false)
          ctx.closePath()
          ctx.fill()
          ctx.globalAlpha = 1
        }

        Text {
          anchors.centerIn: parent
          visible: !root.idle
          text: Model.formatRemaining(root.remaining)
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Math.round(panel.discSize * 0.16)
          style: Text.Outline
          styleColor: Color.menu.background
        }

        Text {
          anchors.centerIn: parent
          visible: root.idle && root.customMinutes !== ""
          text: root.customMinutes + " min"
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Math.round(panel.discSize * 0.14)
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.statusText
        textFormat: Text.PlainText
        color: root.paused ? root.dim : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.idle
        spacing: Style.space(8)

        Repeater {
          model: root.presets

          Button {
            required property int modelData
            text: modelData + "m"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.heading
            onClicked: root.startTimer(modelData)
          }
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.idle
          ? (root.customMinutes === ""
            ? "Pick a preset, or type minutes and press Enter · Esc close"
            : "Enter start · Backspace edit · Esc close")
          : "Space pause · +/− adjust 5m · C cancel · Esc close"
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    SequentialAnimation {
      id: pulse
      property real opacityValue: 1
      running: root.opened && root.closing
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { target: pulse; property: "opacityValue"; from: 1; to: 0.45; duration: 500; easing.type: Easing.InOutSine }
      NumberAnimation { target: pulse; property: "opacityValue"; from: 0.45; to: 1; duration: 500; easing.type: Easing.InOutSine }
    }
  }
}
