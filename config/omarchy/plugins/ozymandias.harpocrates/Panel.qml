import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "ozymandias.harpocrates"
  ipcTarget: "ozymandias.harpocrates"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.55)
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property bool recording: false
  property string phase: "idle"
  property string activeMode: "meeting"
  property double startedAt: 0
  property int elapsedSec: 0
  property string selectedMode: "meeting"
  property string notePath: ""
  property var recentLines: []

  property var notesList: []
  property int selectedNoteIndex: -1
  readonly property var selectedNote: (selectedNoteIndex >= 0 && selectedNoteIndex < notesList.length)
    ? notesList[selectedNoteIndex]
    : null

  property bool summarizing: false
  property string summaryMessage: ""
  property bool summaryIsError: false
  property bool showSummaryTab: false

  readonly property string outputDir: setting("outputDir", "")
  readonly property string modelSize: setting("model", "small")
  readonly property string binPath: Quickshell.env("HOME") + "/.local/bin/harpocrates"

  function formatDuration(sec) {
    var s = Math.max(0, Math.floor(sec))
    var m = Math.floor(s / 60)
    var r = s % 60
    return (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r
  }

  onOpenedChanged: {
    if (opened) {
      stickyWindow.updateAnchorPos()
      refreshStatus()
      refreshNotes()
    }
  }

  onRecordingChanged: {
    if (!recording) refreshNotes()
  }

  onSelectedNoteIndexChanged: {
    root.summaryMessage = ""
    root.summaryIsError = false
    if (root.selectedNote && root.selectedNote.has_summary) {
      root.showSummaryTab = true
    } else {
      root.showSummaryTab = false
    }
  }

  function refreshStatus() {
    if (statusProc.running) return
    statusProc.running = true
  }

  function refreshNotes() {
    if (notesProc.running) return
    var cmd = [root.binPath, "notes", "--limit", "25"]
    if (root.outputDir !== "") cmd.push("--output-dir", root.outputDir)
    notesProc.command = cmd
    notesProc.running = true
  }

  function startNewRecording() {
    if (actionProc.running || root.recording) return
    root.recording = true
    root.phase = "starting"
    root.activeMode = root.selectedMode
    root.startedAt = Date.now() / 1000.0
    root.elapsedSec = 0
    root.recentLines = []
    root.summaryMessage = ""

    var lang = root.selectedMode === "meeting" ? "pt" : "en"
    var args = [
      root.binPath, "start",
      "--background",
      "--mode", root.selectedMode,
      "--lang", lang,
      "--model", root.modelSize
    ]
    if (root.outputDir !== "") args.push("--output-dir", root.outputDir)
    actionProc.command = args
    actionProc.running = true
  }

  function resumeNote(noteObj) {
    if (!noteObj || actionProc.running || root.recording) return
    var mode = noteObj.mode || root.selectedMode
    var lang = mode === "meeting" ? "pt" : "en"
    root.recording = true
    root.phase = "starting"
    root.activeMode = mode
    root.notePath = noteObj.path
    root.startedAt = Date.now() / 1000.0
    root.elapsedSec = 0
    root.recentLines = noteObj.preview || []
    root.summaryMessage = ""

    var args = [
      root.binPath, "start",
      "--background",
      "--mode", mode,
      "--lang", lang,
      "--model", root.modelSize,
      "--note-path", noteObj.path
    ]
    if (root.outputDir !== "") args.push("--output-dir", root.outputDir)
    actionProc.command = args
    actionProc.running = true
  }

  function stopRecording() {
    if (actionProc.running) return
    root.phase = "stopping"
    actionProc.command = [root.binPath, "stop"]
    actionProc.running = true
  }

  function summarizePath(targetPath) {
    if (!targetPath || root.summarizing || summarizeProc.running) return
    root.summarizing = true
    root.summaryIsError = false
    root.summaryMessage = "Summarizing with local Ollama..."
    summarizeProc.command = [root.binPath, "summarize", targetPath]
    summarizeProc.running = true
  }

  function openPath(path) {
    if (!path) return
    Quickshell.execDetached(["xdg-open", path])
  }

  Timer {
    interval: root.recording ? 1000 : 4000
    running: root.opened || root.recording
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.refreshStatus()
      if (root.recording && root.startedAt > 0) {
        root.elapsedSec = Math.max(0, Math.floor(Date.now() / 1000.0 - root.startedAt))
      }
    }
  }

  Process {
    id: statusProc
    command: [root.binPath, "status", "--tail", "40"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "{}"))
          root.recording = parsed.recording === true
          root.phase = parsed.phase || "idle"
          root.activeMode = parsed.mode || root.selectedMode
          root.notePath = parsed.note_path || ""
          root.startedAt = Number(parsed.started_at || 0)
          if (root.recording && root.startedAt > 0) {
            root.elapsedSec = Math.max(0, Math.floor(Date.now() / 1000.0 - root.startedAt))
          } else {
            root.elapsedSec = 0
          }
          root.recentLines = parsed.recent || []
        } catch (e) {}
      }
    }
  }

  Process {
    id: notesProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var list = JSON.parse(String(text || "[]"))
          root.notesList = Array.isArray(list) ? list : []
          if (root.notesList.length === 0) {
            root.selectedNoteIndex = -1
          } else if (root.selectedNoteIndex < 0 || root.selectedNoteIndex >= root.notesList.length) {
            root.selectedNoteIndex = 0
          }
        } catch (e) {}
      }
    }
  }

  Process {
    id: actionProc
    onExited: {
      Qt.callLater(root.refreshStatus)
      Qt.callLater(root.refreshNotes)
    }
  }

  Process {
    id: summarizeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.summarizing = false
        try {
          var res = JSON.parse(String(text || "{}"))
          if (res.ok) {
            root.summaryIsError = false
            root.summaryMessage = "Summary saved (" + (res.model || "ollama") + ")"
            root.showSummaryTab = true
            root.refreshNotes()
          } else {
            root.summaryIsError = true
            root.summaryMessage = res.error || "Summary failed"
          }
        } catch (e) {
          root.summaryIsError = true
          root.summaryMessage = "Unexpected response from summarize"
        }
      }
    }
  }

  // Sticky always-on-top panel window: does NOT steal keyboard focus or close
  // on outside clicks / workspace switches. Only closes via bar icon or "✕".
  PanelWindow {
    id: stickyWindow

    readonly property var anchorWindow: root.anchorItem ? root.anchorItem.QsWindow.window : null
    readonly property string barPos: root.bar ? root.bar.position : "top"
    readonly property real screenW: screen ? screen.width : 0
    readonly property real screenH: screen ? screen.height : 0
    readonly property real barW: anchorWindow ? anchorWindow.width : 0
    readonly property real barH: anchorWindow ? anchorWindow.height : 0
    readonly property int margin: Style.gapsOut
    readonly property int gap: Style.gapsOut
    readonly property int cardWidth: Math.min(Style.space(470), Math.max(240, screenW - margin * 2))
    readonly property int cardHeight: Math.min(contentCol.implicitHeight + card.padding * 2 + Border.top(card.borderSpec) + Border.bottom(card.borderSpec), Math.max(240, screenH - barH - gap - margin))

    property point anchorPos: Qt.point(0, 0)

    function updateAnchorPos() {
      if (root.anchorItem && anchorWindow && anchorWindow.contentItem) {
        anchorPos = root.anchorItem.mapToItem(anchorWindow.contentItem, 0, 0)
      }
    }

    readonly property point cardOrigin: {
      var x = screenW - cardWidth - margin
      var y = barH + gap
      if (root.anchorItem && root.bar) {
        var aw = root.anchorItem.width
        var ah = root.anchorItem.height
        if (barPos === "bottom") {
          x = anchorPos.x + aw / 2 - cardWidth / 2
          y = screenH - barH - cardHeight - gap
        } else if (barPos === "left") {
          x = barW + gap
          y = anchorPos.y + ah / 2 - cardHeight / 2
        } else if (barPos === "right") {
          x = screenW - barW - cardWidth - gap
          y = anchorPos.y + ah / 2 - cardHeight / 2
        } else {
          x = anchorPos.x + aw / 2 - cardWidth / 2
          y = barH + gap
        }
      }
      x = Math.max(margin, Math.min(x, screenW - cardWidth - margin))
      y = Math.max(margin, Math.min(y, screenH - cardHeight - margin))
      return Qt.point(Math.round(x), Math.round(y))
    }

    screen: anchorWindow ? anchorWindow.screen : null
    visible: root.opened || card.opacity > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "omarchy-harpocrates-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    mask: Region {
      item: card
    }

    BorderSurface {
      id: card
      x: stickyWindow.cardOrigin.x
      y: stickyWindow.cardOrigin.y
      width: stickyWindow.cardWidth
      height: stickyWindow.cardHeight
      color: Commons.Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.popupPadding
      radius: Style.cornerRadius
      opacity: root.opened ? 1.0 : 0.0

      Behavior on opacity {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }

      ColumnLayout {
        id: contentCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 0
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.space(10)

        // Header
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            text: root.recording
              ? "󰑊  Recording · " + root.activeMode.toUpperCase() + " · " + root.formatDuration(root.elapsedSec)
              : "󰑊  Harpocrates"
            color: root.recording ? root.urgent : root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.fillWidth: true
          }

          Text {
            visible: root.recording
            text: root.phase
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          PanelActionButton {
            iconText: "✕"
            tooltipText: "Close panel"
            foreground: root.fg
            onClicked: root.close()
          }
        }

        // Feedback banner for summarize action
        Text {
          Layout.fillWidth: true
          visible: root.summaryMessage !== ""
          wrapMode: Text.WordWrap
          text: root.summaryMessage
          color: root.summaryIsError ? root.urgent : root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // ACTIVE RECORDING VIEW
        ColumnLayout {
          Layout.fillWidth: true
          visible: root.recording
          spacing: Style.space(8)

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Text {
              text: root.notePath ? root.notePath.split("/").pop() : "Initializing note..."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
              Layout.fillWidth: true
            }

            Button {
              text: "Stop"
              iconText: "󰓛"
              bordered: true
              selected: true
              accent: root.urgent
              onClicked: root.stopRecording()
            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(280)
            color: Qt.rgba(0, 0, 0, 0.24)
            radius: Style.cornerRadius
            border.width: 1
            border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)

            ListView {
              id: liveTranscriptList
              anchors.fill: parent
              anchors.margins: Style.space(10)
              clip: true
              spacing: Style.space(6)
              model: root.recentLines
              onCountChanged: Qt.callLater(() => liveTranscriptList.positionViewAtEnd())
              Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

              delegate: Text {
                width: liveTranscriptList.width - Style.space(8)
                wrapMode: Text.WordWrap
                text: "[" + modelData.time + "] " + modelData.speaker + ": " + modelData.text
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                anchors.centerIn: parent
                width: parent.width - Style.space(20)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: root.recentLines.length === 0
                text: root.phase === "loading model" || root.phase === "starting"
                  ? "Loading local Whisper model..."
                  : "Listening... speak or play audio to see live lines."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Button {
              text: root.summarizing ? "Summarizing..." : "Summarize"
              iconText: "✦"
              bordered: true
              enabled: !root.summarizing && root.notePath !== "" && root.recentLines.length > 0
              onClicked: root.summarizePath(root.notePath)
            }

            Item { Layout.fillWidth: true }

            Button {
              text: "Open Note"
              bordered: true
              enabled: root.notePath !== ""
              onClicked: root.openPath(root.notePath)
            }
          }
        }

        // IDLE VIEW: NEW RECORDING + RESUME / SUMMARIZE EXISTING NOTE
        ColumnLayout {
          Layout.fillWidth: true
          visible: !root.recording
          spacing: Style.space(10)

          // New recording controls
          Rectangle {
            Layout.fillWidth: true
            implicitHeight: newRecRow.implicitHeight + Style.space(16)
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
            radius: Style.cornerRadius
            border.width: 1
            border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)

            RowLayout {
              id: newRecRow
              anchors.fill: parent
              anchors.margins: Style.space(8)
              spacing: Style.space(6)

              Button {
                text: "Meeting (PT/EN)"
                bordered: true
                selected: root.selectedMode === "meeting"
                onClicked: root.selectedMode = "meeting"
              }

              Button {
                text: "Video (EN)"
                bordered: true
                selected: root.selectedMode === "video"
                onClicked: root.selectedMode = "video"
              }

              Item { Layout.fillWidth: true }

              Button {
                text: "New Note"
                iconText: "󰑊"
                bordered: true
                selected: true
                accent: root.accent
                onClicked: root.startNewRecording()
              }
            }
          }

          // Existing notes list header
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Text {
              text: "Saved Voice Notes (" + root.notesList.length + ")"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              Layout.fillWidth: true
            }

            PanelActionButton {
              iconText: "↻"
              tooltipText: "Refresh notes"
              foreground: root.fg
              onClicked: root.refreshNotes()
            }
          }

          // Notes list
          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(150)
            color: Qt.rgba(0, 0, 0, 0.20)
            radius: Style.cornerRadius
            border.width: 1
            border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)

            ListView {
              id: notesListView
              anchors.fill: parent
              anchors.margins: Style.space(6)
              clip: true
              spacing: Style.space(4)
              model: root.notesList
              Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

              delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property bool isSel: index === root.selectedNoteIndex
                width: notesListView.width - Style.space(6)
                height: Style.space(36)
                radius: Style.cornerRadius
                color: isSel
                  ? Style.selectedFillFor(root.fg, root.accent)
                  : (rowMouse.containsMouse ? Style.hoverFillFor(root.fg, root.accent) : "transparent")

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(8)

                  Text {
                    text: (modelData.has_summary ? "✦ " : "") + modelData.stem
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: isSel
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }

                  Text {
                    text: modelData.mode + " · " + modelData.lines + " lines"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: root.selectedNoteIndex = index
                }
              }

              Text {
                anchors.centerIn: parent
                visible: root.notesList.length === 0
                text: "No voice notes yet in 05 - Fleeting/voice notes"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          // Preview header (Summary vs Transcript toggle when a summary exists)
          RowLayout {
            Layout.fillWidth: true
            visible: root.selectedNote !== null
            spacing: Style.space(6)

            Button {
              text: "Summary"
              bordered: true
              selected: root.showSummaryTab
              enabled: root.selectedNote && root.selectedNote.has_summary
              onClicked: root.showSummaryTab = true
            }

            Button {
              text: "Transcript"
              bordered: true
              selected: !root.showSummaryTab
              onClicked: root.showSummaryTab = false
            }

            Item { Layout.fillWidth: true }
          }

          // Selected note preview
          Rectangle {
            Layout.fillWidth: true
            visible: root.selectedNote !== null
            Layout.preferredHeight: Style.space(145)
            color: Qt.rgba(0, 0, 0, 0.16)
            radius: Style.cornerRadius
            border.width: 1
            border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)

            Controls.ScrollView {
              anchors.fill: parent
              anchors.margins: Style.space(8)
              visible: root.showSummaryTab && root.selectedNote && root.selectedNote.has_summary
              clip: true

              Text {
                width: parent.width - Style.space(10)
                wrapMode: Text.WordWrap
                text: root.selectedNote ? (root.selectedNote.summary || "") : ""
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            ListView {
              anchors.fill: parent
              anchors.margins: Style.space(8)
              visible: !root.showSummaryTab || !(root.selectedNote && root.selectedNote.has_summary)
              clip: true
              spacing: Style.space(4)
              model: root.selectedNote ? (root.selectedNote.preview || []) : []
              Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

              delegate: Text {
                width: parent ? parent.width - Style.space(6) : 300
                wrapMode: Text.WordWrap
                text: "[" + modelData.time + "] " + modelData.speaker + ": " + modelData.text
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.centerIn: parent
                visible: root.selectedNote && (!root.selectedNote.preview || root.selectedNote.preview.length === 0)
                text: "Note has no transcript lines yet."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)
            visible: root.selectedNote !== null

            Button {
              text: "Resume Note"
              iconText: "󰐊"
              bordered: true
              onClicked: root.resumeNote(root.selectedNote)
            }

            Button {
              text: root.summarizing ? "Summarizing..." : "Summarize"
              iconText: "✦"
              bordered: true
              enabled: !root.summarizing && root.selectedNote && root.selectedNote.lines > 0
              onClicked: root.summarizePath(root.selectedNote.path)
            }

            Item { Layout.fillWidth: true }

            Button {
              text: "Open"
              bordered: true
              onClicked: root.openPath(root.selectedNote.path)
            }
          }
        }
      }
    }
  }
}
