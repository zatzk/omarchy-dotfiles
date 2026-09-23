import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "../Safe.js" as Safe

// Quick-capture inbox: summon, type the thought, Enter, gone. The whole
// point is beating working memory to the punch — the thought is written down
// before the context switch can eat it. Shift+Enter saves and stays open.
//
// Payload keys: "file" (capture target, default ~/Documents/inbox.md),
// "fontFamily".
Item {
  id: root

  signal dismissRequested()

  readonly property string home: Quickshell.env("HOME")

  property bool opened: false
  property string inputText: ""
  property string captureFile: root.defaultFile
  property string fontFamily: Style.font.menuFamily
  property bool flashing: false

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  // Wide enough that the footer — inbox path plus key hints — fits on one
  // line at body-small, and that a typical one-line thought does not elide.
  property int cardWidth: Math.min(Style.space(440), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(contentMargin * 2 + headerHeight + hintRow.implicitHeight + Style.space(6), panel.height - Style.gapsOut * 2)

  readonly property string defaultFile: root.home + "/Documents/inbox.md"

  // Shown in the footer, so it is bounded and stripped of anything a text
  // sink could read as markup — the path came from the summon payload.
  readonly property string fileLabel: {
    var f = root.captureFile
    var shown = f.indexOf(root.home) === 0 ? "~" + f.slice(root.home.length) : f
    return Safe.plainLabel(shown, Safe.LIMITS.label)
  }

  function expandPath(path) {
    var p = String(path || "")
    if (p === "~") return root.home
    if (p.indexOf("~/") === 0) return root.home + p.slice(1)
    return p
  }

  function openView(payload) {
    var family = Safe.bounded(payload.fontFamily, Safe.LIMITS.fontFamily)
    if (family) root.fontFamily = family

    // A path the payload cannot vouch for (control characters, absurd
    // length) is refused rather than rewritten: appending the thought to a
    // quietly different file is worse than using the default inbox.
    var wanted = Safe.payloadPath(payload.file)
    root.captureFile = wanted ? expandPath(wanted) : root.defaultFile

    root.opened = true
    root.inputText = ""
    root.flashing = false
    flashTimer.stop()
    dismissTimer.stop()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    root.dismissRequested()
  }

  function submit(stayOpen) {
    var thought = root.inputText.trim()
    if (!thought) {
      root.dismiss()
      return
    }

    // Appended via positional args so the thought is data, never shell
    // syntax — apostrophes, quotes and $ all land in the file verbatim.
    var line = "- [ ] " + Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm") + " " + thought
    Quickshell.execDetached([
      "sh", "-c",
      'mkdir -p "$(dirname "$1")" && printf \'%s\\n\' "$2" >> "$1"',
      "sh", root.captureFile, line
    ])

    root.inputText = ""
    root.flashing = true
    flashTimer.restart()
    if (!stayOpen) dismissTimer.restart()
  }

  Timer {
    id: flashTimer
    interval: 550
    onTriggered: root.flashing = false
  }

  // The checkmark gets one beat on screen before the card goes — enough to
  // confirm the save without turning capture into a wait.
  Timer {
    id: dismissTimer
    interval: 280
    onTriggered: root.dismiss()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "adhd-kit-capture"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.inputText) root.inputText = ""
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.submit((event.modifiers & Qt.ShiftModifier) !== 0)
            event.accepted = true
          } else if (Util.editsFilter(event, root.inputText)) {
            root.inputText = Util.editedFilter(event, root.inputText)
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.inputText += event.text
            event.accepted = true
          }
        }
      }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Text {
          id: promptLine
          anchors.left: parent.left
          anchors.right: checkmark.visible ? checkmark.left : parent.right
          anchors.top: parent.top
          height: root.headerHeight
          verticalAlignment: Text.AlignVCenter
          text: root.inputText || "Capture a thought..."
          textFormat: Text.PlainText
          color: root.foreground
          opacity: root.inputText ? 1 : 0.58
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          elide: Text.ElideLeft
        }

        Text {
          id: checkmark
          anchors.right: parent.right
          anchors.verticalCenter: promptLine.verticalCenter
          visible: root.flashing
          text: "✓"
          textFormat: Text.PlainText
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
        }

        Text {
          id: hintRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          text: root.fileLabel + " · ⏎ save · ⇧⏎ next · Esc"
          textFormat: Text.PlainText
          color: root.foreground
          opacity: 0.4
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideMiddle
        }
      }
    }
  }
}
