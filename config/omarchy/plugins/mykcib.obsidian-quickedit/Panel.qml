import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Obsidian quick note popup: vault scan + note picker on the left, a plain
// text editor on the right. The bar button's click goes straight to the last
// edited note when one is configured; the picker is one click away via the
// back button in the editor header.
//
// Notes are plain .md files read and written in place with FileView
// (atomicWrites), so external editors — Obsidian itself — stay consistent.
Panel {
  id: root
  moduleName: "mykcib.obsidian-quickedit"
  ipcTarget: "mykcib.obsidian-quickedit"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.55)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string vaultPath: Model.normalizeVaultPath(Model.expandPath(setting("vaultPath", ""), Quickshell.env("HOME")))
  readonly property string configuredNote: Model.expandPath(setting("notePath", ""), Quickshell.env("HOME"))

  // When no vault is configured, look for one on disk (directories carrying
  // a .obsidian marker) so a fresh install works without touching settings.
  property var detectedVaults: []
  property bool detectingVaults: false
  property bool detectionStarted: false
  readonly property string detectedVault: detectedVaults.length > 0 ? String(detectedVaults[0]) : ""
  readonly property string effectiveVault: Model.normalizeVaultPath(root.vaultPath !== "" ? root.vaultPath : root.detectedVault)
  readonly property bool vaultConfigured: effectiveVault !== ""

  // In-panel vault editor: type a path when none is pinned, or edit the
  // pinned one via the footer's Change button. Persisted on commit.
  property bool editingVaultPath: false
  property string vaultPendingError: ""

  // Once detection finds a vault, prefill the input so one "Use" click pins
  // it. Never clobber something the user already typed.
  onDetectedVaultsChanged: {
    if (root.vaultPath !== "" || !vaultField || vaultField.text !== "") return
    Qt.callLater(function() {
      if (vaultField && vaultField.text === "" && root.detectedVault !== "")
        vaultField.text = root.detectedVault
    })
  }

  // ---- picker state
  property var notes: []
  property bool scanning: false
  property bool rescanQueued: false
  property string filterText: ""
  property string activeTag: "all"
  property int pickIndex: 0
  readonly property var availableTags: Model.getAvailableTags(notes)
  readonly property var pickRows: Model.filterNotes(notes, filterText, activeTag)

  // ---- editor state
  property bool editing: false
  property bool loadingNote: false
  property bool noteMissing: false
  property string editRel: ""
  property bool dirty: false
  property bool saveFailedState: false
  property bool justSaved: false
  property bool syncingText: false
  property string moveNotice: ""
  property bool movingNote: false
  property string moveTargetRel: ""

  readonly property string editPath: editRel === "" ? "" : Model.joinPath(effectiveVault, (editRel.indexOf("/") === -1 ? "quicknotes/" + editRel : editRel))

  // ---------------------------------------------------------------- lifecycle

  function open() {
    root.controller.show()
    Qt.callLater(root.enterView)
  }

  function close() {
    if (root.dirty && root.editPath !== "") root.saveNote()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  onOpenedChanged: function() {
    if (!root.opened) {
      root.filterText = ""
      root.pickIndex = 0
      root.justSaved = false
      root.saveFailedState = false
      root.moveNotice = ""
    }
  }

  // On open: skip straight to the configured note when it exists; otherwise
  // land on the picker (which rescans the vault if the cache is empty).
  function enterView() {
    if (!root.opened) return
    if (root.editRel !== "") {
      root.beginEdit()
      return
    }
    var next = Model.toRel(root.effectiveVault, root.configuredNote)
    if (next !== "") {
      if (next.indexOf("/") === -1 && next.endsWith(".md")) {
        next = "quicknotes/" + next
      }
      root.editRel = next
      root.pinDetectedVaultIfUsed()
      root.beginEdit()
      return
    }
    if (root.vaultConfigured) root.loadNotes()
    root.focusPicker()
  }

  function focusPicker() {
    Qt.callLater(function() {
      if (!root.opened) return
      if (pickerField) pickerField.forceActiveFocus()
      else keyCatcher.forceActiveFocus()
    })
  }

  // ---------------------------------------------------------------- notes

  function loadNotes() {
    if (!root.vaultConfigured) return
    if (notesProc.running) {
      root.rescanQueued = true
      return
    }
    root.scanning = true
    notesProc.command = ["bash", "-c", "cd " + Util.shellQuote(root.effectiveVault)
      + " && find . -type f -name '*.md' 2>/dev/null | LC_ALL=C sort -r"]
    notesProc.running = true
  }

  // Best-effort vault discovery for fresh installs: common home locations,
  // plus a shallow sweep of $HOME itself. Only runs when no vault is pinned.
  function maybeRunVaultDetection() {
    if (root.vaultPath !== "" || root.detectionStarted) return
    root.detectionStarted = true
    root.detectingVaults = true
    detectProc.command = ["bash", "-c",
      "for d in \"$HOME/Documents\" \"$HOME/Notes\" \"$HOME/Obsidian\"; do "
      + "find \"$d\" -maxdepth 4 -name .obsidian -type d 2>/dev/null; done; "
      + "find \"$HOME\" -maxdepth 3 -name .obsidian -type d 2>/dev/null | sort -u"]
    detectProc.running = true
  }

  function pickRel(index) {
    if (index < 0 || index >= root.pickRows.length) return ""
    return String(root.pickRows[index].rel || "")
  }

  function activatePick() {
    var rel = root.pickRel(root.pickIndex)
    if (rel === "") return
    root.persistNote(rel)
    root.editRel = rel
    root.beginEdit()
  }

  function movePick(delta) {
    if (root.pickRows.length === 0) return
    root.pickIndex = Math.max(0, Math.min(root.pickRows.length - 1, root.pickIndex + delta))
  }

  function goPicker() {
    root.editing = false
    root.editRel = ""
    root.loadingNote = false
    root.noteMissing = false
    root.dirty = false
    root.saveFailedState = false
    root.justSaved = false
    if (root.vaultConfigured) root.loadNotes()
    root.focusPicker()
  }

  // Write an update to the bar's inline shell.json entry, merged with the
  // current settings, and echo it locally so bindings react immediately.
  function persistEntry(patch) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    for (var p in patch) entry[p] = patch[p]
    root.settings = entry
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // A note picked from a detected vault pins that vault too, so the choice
  // survives without the extra "Use" click.
  function pinDetectedVaultIfUsed() {
    if (String(root.settings.vaultPath || "") !== "") return
    if (root.detectedVault === "") return
    root.persistEntry({ vaultPath: Model.normalizeVaultPath(root.detectedVault) })
  }

  function persistNote(rel) {
    if (rel === "") return
    var v = String(root.settings.vaultPath || "") !== "" ? root.settings.vaultPath : root.detectedVault
    root.persistEntry({
      vaultPath: Model.normalizeVaultPath(v),
      notePath: rel
    })
  }

  // The raw string is stored so ~ and $HOME expand on every read, like the
  // settings form does.
  function persistVault(raw) {
    root.persistEntry({ vaultPath: Model.normalizeVaultPath(raw) })
  }

  function startVaultEdit() {
    // The vault field lives in the picker view; from the editor, switch
    // there first (saving any pending edits) so the field is visible.
    if (root.editing) {
      if (root.dirty && root.editPath !== "") root.saveNote()
      root.goPicker()
    }
    root.editingVaultPath = true
    Qt.callLater(root.focusVaultField)
  }

  function focusVaultField() {
    if (!vaultField || !vaultField.visible) return
    vaultField.text = root.vaultPath
    vaultField.forceActiveFocus()
    vaultField.selectAll()
  }

  function cancelVaultEdit() {
    root.editingVaultPath = false
    root.vaultPendingError = ""
  }

  // Commit whatever is in the vault field, rescan the folder, and persist.
  function commitVault() {
    var raw = String(vaultField.text || "").trim()
    if (raw === "") return
    var expanded = Model.normalizeVaultPath(Model.expandPath(raw, Quickshell.env("HOME")))
    if (expanded !== root.effectiveVault) {
      // A different vault invalidates the note picked from the old one.
      root.editRel = ""
      root.editing = false
    }
    root.vaultPendingError = ""
    root.filterText = ""
    root.pickIndex = 0
    root.notes = []
    root.persistVault(expanded)
    root.editingVaultPath = false
    root.loadNotes()
    root.focusPicker()
  }

  // ---------------------------------------------------------------- editor

  function beginEdit() {
    if (root.editRel === "") return
    root.editing = true
    root.loadingNote = true
    root.noteMissing = false
    root.justSaved = false
    root.saveFailedState = false
    root.dirty = false
    if (editorScroll && editorScroll.contentItem) editorScroll.contentItem.contentY = 0
    noteFile.reload()
  }

  function saveNote() {
    if (!root.dirty || root.editPath === "" || root.loadingNote) return
    noteFile.setText(editor.text)
    root.dirty = false
    root.saveFailedState = false
    root.justSaved = true
    savedFlashTimer.restart()
  }

  function markDirty() {
    if (root.syncingText) return
    if (!root.dirty) root.dirty = true
    root.saveFailedState = false
    if (root.justSaved) { root.justSaved = false; savedFlashTimer.stop() }
  }

  Component.onCompleted: Qt.callLater(root.maybeRunVaultDetection)

  Process {
    id: detectProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.detectedVaults = Model.parseVaultCandidates(text)
        root.detectingVaults = false
        if (root.vaultConfigured && root.opened && root.notes.length === 0) root.loadNotes()
      }
    }
  }

  Process {
    id: notesProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.notes = Model.parseNotes(text, root.effectiveVault)
        root.scanning = false
        if (root.pickIndex >= root.pickRows.length) root.pickIndex = Math.max(0, root.pickRows.length - 1)
        if (root.rescanQueued) {
          root.rescanQueued = false
          Qt.callLater(root.loadNotes)
        }
      }
    }
    onExited: function(exitCode) {
      root.scanning = false
      if (exitCode !== 0 && root.notes.length === 0 && root.vaultConfigured)
        root.vaultPendingError = "Could not read this folder as a vault: " + root.effectiveVault
    }
  }

  FileView {
    id: noteFile
    path: root.editPath
    atomicWrites: true
    printErrors: false
    onLoaded: {
      if (root.editRel === "") return
      root.syncingText = true
      editor.text = String(noteFile.text() || "")
      root.syncingText = false
      root.loadingNote = false
      root.noteMissing = false
      root.dirty = false
      root.justSaved = false
      Qt.callLater(function() {
        if (root.opened && root.editing && editor.visible) editor.forceActiveFocus()
      })
    }
    onLoadFailed: {
      if (root.editRel === "") return
      root.loadingNote = false
      root.noteMissing = true
      root.dirty = false
      if (root.editRel === Model.toRel(root.effectiveVault, root.configuredNote)) {
        root.persistEntry({ notePath: "" })
        root.goPicker()
      }
    }
    onSaveFailed: {
      if (root.editing && root.editPath !== "") {
        root.dirty = true
        root.saveFailedState = true
        root.justSaved = false
        savedFlashTimer.stop()
      }
    }
  }

  Timer {
    id: savedFlashTimer
    interval: 1500
    onTriggered: root.justSaved = false
  }

  Process {
    id: moveNoteProc
    onExited: function(code) {
      root.movingNote = false
      if (code === 0) {
        var oldConfiguredRel = Model.toRel(root.effectiveVault, root.configuredNote)
        var oldEditRel = root.editRel
        root.editRel = root.moveTargetRel
        if (oldEditRel === oldConfiguredRel || ("quicknotes/" + oldEditRel) === oldConfiguredRel) {
          root.persistNote(root.moveTargetRel)
        }
        root.loadNotes()
        root.moveNotice = "Moved to " + Model.tagLabel(Model.getTag(root.moveTargetRel))
        moveFlashTimer.restart()
      } else {
        root.vaultPendingError = "Failed to move note"
      }
    }
  }

  Timer {
    id: moveFlashTimer
    interval: 2000
    onTriggered: root.moveNotice = ""
  }

  function moveNoteToTag(newTag) {
    if (root.editRel === "" || root.movingNote) return
    var curTag = Model.getTag(root.editRel)
    if (curTag === newTag) return

    if (root.dirty) {
      root.saveNote()
    }

    var filename = Model.getFilename(root.editRel)
    var newRel = Model.buildRelPath(newTag, filename)
    root.moveTargetRel = newRel

    var actualOldRel = root.editRel.indexOf("/") === -1 ? "quicknotes/" + root.editRel : root.editRel
    var oldFullPath = Model.joinPath(root.effectiveVault, actualOldRel)
    var newFullPath = Model.joinPath(root.effectiveVault, newRel)

    root.movingNote = true
    moveNoteProc.command = ["bash", "-c", "mkdir -p \"$(dirname \"$2\")\" && mv \"$1\" \"$2\"", "_", oldFullPath, newFullPath]
    moveNoteProc.running = true
  }

  property string newNotePendingRel: ""

  Process {
    id: createNoteProc
    onExited: function(code) {
      if (code === 0) {
        root.loadNotes()
        root.editRel = root.newNotePendingRel
        root.beginEdit()
      } else {
        root.vaultPendingError = "Failed to create note"
      }
    }
  }

  function createNewNote() {
    var folder = root.activeTag !== "" && root.activeTag !== "all" ? root.activeTag : "quicknotes"
    var title = "QuickNote-" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HHmmss")
    var newRel = folder + "/" + title + ".md"
    root.newNotePendingRel = newRel
    var fullPath = Model.joinPath(root.effectiveVault, newRel)
    createNoteProc.command = ["bash", "-c", "mkdir -p \"$(dirname \"$1\")\" && touch \"$1\"", "_", fullPath]
    createNoteProc.running = true
  }

  Process {
    id: deleteNoteProc
    onExited: function(code) {
      if (code === 0) {
        root.loadNotes()
      } else {
        root.vaultPendingError = "Failed to delete note"
      }
    }
  }

  function deleteNoteAt(index) {
    var rel = root.pickRel(index)
    if (rel === "") return
    if (rel === Model.toRel(root.effectiveVault, root.configuredNote)) {
      root.persistEntry({ notePath: "" })
    }
    if (root.editRel === rel) {
      root.goPicker()
    }
    var fullPath = Model.joinPath(root.effectiveVault, rel)
    deleteNoteProc.command = ["rm", "-f", fullPath]
    deleteNoteProc.running = true
  }

  IpcHandler {
    target: "mykcib.obsidian-quickedit"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }

    function toggleNewNote(): void {
      if (root.opened) {
        root.close()
      } else {
        root.open()
        Qt.callLater(function() {
          root.createNewNote()
        })
      }
    }

    function toggleSearchList(): void {
      if (root.opened) {
        if (root.editing) {
          root.goPicker()
        } else {
          root.close()
        }
      } else {
        root.open()
        Qt.callLater(function() {
          root.goPicker()
        })
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: (!root.editing && (pickerField.activeFocus || vaultField.activeFocus))
        || (root.editing && editor.activeFocus)
      onMoveRequested: function(dx, dy) {
        if (!root.editing && dy !== 0 && root.pickRows.length > 0) root.movePick(dy)
      }
      onActivateRequested: if (!root.editing) root.activatePick()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ---------- Header ----------
          Item {
            width: parent.width
            implicitHeight: headerBlock.implicitHeight

            Column {
              id: headerBlock
              anchors.left: parent.left
              anchors.right: backButton.visible ? backButton.left : parent.right
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: "QUICK NOTE"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
                font.letterSpacing: 1
                elide: Text.ElideRight
              }

              Text {
                visible: root.editing && root.editRel !== ""
                width: parent.width
                text: root.editRel
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideMiddle
              }
            }

            PanelActionButton {
              id: backButton
              visible: root.editing
              anchors.top: parent.top
              anchors.right: parent.right
              iconText: "󰅁"
              tooltipText: "All notes"
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.goPicker()
            }
          }

          // ---------- Picker ----------
          Column {
            visible: !root.editing
            width: parent.width
            spacing: Style.space(8)

            // Vault input: always present until a vault is pinned; also
            // reachable via the footer's Change button once pinned.
            Column {
              visible: root.vaultPath === "" || root.editingVaultPath
              width: parent.width
              spacing: Style.space(6)

              RowLayout {
                width: parent.width
                spacing: Style.space(6)

                TextField {
                  id: vaultField
                  Layout.fillWidth: true
                  placeholderText: "Vault path… e.g. ~/Documents/Vault"
                  foreground: root.fg
                  font.family: root.fontFamily
                  onAccepted: root.commitVault()
                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                      if (root.editingVaultPath && root.vaultPath !== "") root.cancelVaultEdit()
                      else keyCatcher.forceActiveFocus()
                      event.accepted = true
                    }
                  }
                }

                Button {
                  id: scanButton
                  text: root.vaultPath !== "" ? "Save"
                    : (root.detectedVault !== "" ? "Use" : "Scan")
                  bordered: true
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  verticalPadding: Style.spacing.controlPaddingY
                  onClicked: root.commitVault()
                }

                Button {
                  id: cancelButton
                  visible: root.editingVaultPath && root.vaultPath !== ""
                  text: "Cancel"
                  bordered: true
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  verticalPadding: Style.spacing.controlPaddingY
                  onClicked: root.cancelVaultEdit()
                }
              }

              Text {
                visible: root.vaultPendingError !== ""
                width: parent.width
                text: root.vaultPendingError
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: pickerField
                Layout.fillWidth: true
                enabled: root.vaultConfigured
                placeholderText: "Search notes…"
                text: root.filterText
                foreground: root.fg
                font.family: root.fontFamily
                onTextChanged: {
                  root.filterText = text
                  root.pickIndex = 0
                }
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.activatePick()
                    event.accepted = true
                  } else if (event.key === Qt.Key_Down) {
                    root.movePick(1)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Up) {
                    root.movePick(-1)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Escape) {
                    root.close()
                    event.accepted = true
                  }
                }
              }

              Button {
                id: newNoteButton
                enabled: root.vaultConfigured
                text: "New Note"
                bordered: true
                foreground: root.fg
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.createNewNote()
              }
            }

            // Tag filter bar
            Flickable {
              visible: root.vaultConfigured
              width: parent.width
              height: tagFilterRow.implicitHeight
              contentWidth: tagFilterRow.implicitWidth
              flickableDirection: Flickable.HorizontalFlick
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              Row {
                id: tagFilterRow
                spacing: Style.space(6)

                Repeater {
                  model: ["all"].concat(root.availableTags)
                  delegate: Button {
                    required property string modelData
                    text: Model.tagLabel(modelData)
                    selected: root.activeTag === modelData
                    bordered: true
                    fontSize: Style.font.caption
                    verticalPadding: Style.space(3)
                    horizontalPadding: Style.space(8)
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    onClicked: {
                      root.activeTag = modelData
                      root.pickIndex = 0
                    }
                  }
                }
              }
            }

            Column {
              visible: root.vaultConfigured
              width: parent.width
              spacing: Style.space(4)

              ListView {
                id: pickList
                visible: root.scanning || root.pickRows.length > 0
                width: parent.width
                height: Math.min(contentHeight, Style.space(380))
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                spacing: Style.space(3)
                model: root.pickRows
                currentIndex: root.pickIndex
                onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Item {
                  required property var modelData
                  required property int index

                  width: ListView.view.width
                  height: row.implicitHeight

                  CursorSurface {
                    id: row
                    width: parent.width
                    hasCursor: root.pickIndex === index
                    foreground: root.fg
                    fill: root.hoverFill
                    currentFill: root.selectedFill

                    implicitHeight: rowText.implicitHeight + Style.spacing.rowPaddingX

                    Text {
                      id: rowText
                      anchors.left: parent.left
                      anchors.right: tagBadge.left
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.space(8)
                      anchors.rightMargin: Style.space(6)
                      text: modelData.label
                      color: root.pickIndex === index ? Style.selectedStateColor(root.fg, Color.accent) : root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideMiddle
                    }

                    Rectangle {
                      id: tagBadge
                      anchors.right: parent.right
                      anchors.rightMargin: deleteButton.visible ? Style.space(36) : Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      height: tagBadgeText.implicitHeight + Style.space(4)
                      width: tagBadgeText.implicitWidth + Style.space(8)
                      radius: Style.cornerRadius
                      color: root.pickIndex === index
                        ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.15)
                        : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)

                      Text {
                        id: tagBadgeText
                        anchors.centerIn: parent
                        text: Model.tagLabel(modelData.tag)
                        color: root.pickIndex === index ? root.fg : root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: if (containsMouse) root.pickIndex = index
                    onClicked: {
                      root.pickIndex = index
                      root.activatePick()
                    }
                  }

                  PanelActionButton {
                    id: deleteButton
                    visible: root.pickIndex === index
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: ""
                    tooltipText: "Delete note"
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    onClicked: root.deleteNoteAt(index)
                  }
                }
              }

              Column {
                visible: pickList.visible === false
                width: parent.width
                spacing: Style.space(4)

                Text {
                  visible: root.scanning
                  width: parent.width
                  text: "Scanning vault…"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  visible: !root.scanning && root.notes.length === 0
                  width: parent.width
                  text: "No .md notes found in this vault"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }

                Text {
                  visible: !root.scanning && root.notes.length > 0 && root.pickRows.length === 0
                  width: parent.width
                  text: "No notes match \"" + root.filterText + "\""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }
              }
            }

            Text {
              visible: !root.vaultConfigured
              width: parent.width
              text: root.detectingVaults ? "Looking for an Obsidian vault… or type a path above."
                : root.detectedVault !== "" ? "No notes yet — searching " + root.detectedVault + "…\nType a path above to pin a different vault."
                : "No Obsidian vault found — type the path above, e.g. ~/Documents/Vault"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          // ---------- Editor ----------
          Column {
            visible: root.editing
            width: parent.width
            spacing: Style.space(8)

            Item {
              visible: root.loadingNote || root.noteMissing
              width: parent.width
              implicitHeight: noteStateText.implicitHeight + Style.spacing.lg

              Text {
                id: noteStateText
                width: parent.width - (pickAnotherButton.visible ? pickAnotherButton.width + Style.space(8) : 0)
                text: root.noteMissing ? "Note not found — it may have been moved or deleted." : "Loading…"
                color: root.noteMissing ? root.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }

              Button {
                id: pickAnotherButton
                visible: root.noteMissing
                anchors.right: parent.right
                anchors.top: parent.top
                text: "Pick another note"
                bordered: true
                foreground: root.fg
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.goPicker()
              }
            }

            // Tag switcher for current note
            RowLayout {
              visible: !root.loadingNote && !root.noteMissing && root.editRel !== ""
              width: parent.width
              spacing: Style.space(8)

              Text {
                text: "Tag:"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                Layout.alignment: Qt.AlignVCenter
              }

              Flickable {
                Layout.fillWidth: true
                height: editorTagRow.implicitHeight
                contentWidth: editorTagRow.implicitWidth
                flickableDirection: Flickable.HorizontalFlick
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                  id: editorTagRow
                  spacing: Style.space(6)

                  Repeater {
                    model: root.availableTags
                    delegate: Button {
                      required property string modelData
                      readonly property bool isCurrent: Model.getTag(root.editRel) === modelData
                      text: (isCurrent ? "✓ " : "") + Model.tagLabel(modelData)
                      selected: isCurrent
                      bordered: true
                      fontSize: Style.font.caption
                      verticalPadding: Style.space(3)
                      horizontalPadding: Style.space(8)
                      foreground: root.fg
                      fontFamily: root.fontFamily
                      onClicked: {
                        if (!isCurrent) {
                          root.moveNoteToTag(modelData)
                        }
                      }
                    }
                  }
                }
              }
            }

            ScrollView {
              id: editorScroll
              visible: !root.loadingNote && !root.noteMissing
              width: parent.width
              height: Style.space(400)
              implicitHeight: Style.space(400)
              clip: true
              ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              WheelHandler {
                onWheel: function(event) {
                  var flick = editorScroll.contentItem
                  if (!flick) return
                  var step = -event.angleDelta.y / 2
                  var maxScroll = Math.max(0, flick.contentHeight - editorScroll.height)
                  flick.contentY = Math.max(0, Math.min(maxScroll, flick.contentY + step))
                }
              }

              TextArea {
                id: editor
                width: editorScroll.availableWidth
                wrapMode: Text.Wrap
                selectByMouse: true
                persistentSelection: true
                selectByKeyboard: true
                color: root.fg
                selectionColor: Style.selectionFillFor(root.fg, Color.accent)
                selectedTextColor: root.fg
                placeholderText: "Empty note — start typing…"
                placeholderTextColor: Qt.darker(root.fg, 1.6)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                topPadding: Style.spacing.controlGap
                bottomPadding: Style.spacing.controlGap
                leftPadding: Style.space(10)
                rightPadding: Style.space(14)
                background: BorderSurface {
                  color: Style.controlFill(editor.activeFocus, false, root.fg, Color.accent)
                  borderSpec: Border.controlSpec(editor.activeFocus ? "focus" : "normal", root.fg, Color.accent)
                  radius: Style.cornerRadius
                }

                function ensureCursorVisible() {
                  var flick = editorScroll.contentItem
                  if (!flick) return
                  var curY = cursorRectangle.y
                  var curH = cursorRectangle.height
                  var viewH = editorScroll.height

                  if (curY + curH > flick.contentY + viewH - bottomPadding) {
                    flick.contentY = curY + curH - viewH + bottomPadding
                  } else if (curY < flick.contentY + topPadding) {
                    flick.contentY = Math.max(0, curY - topPadding)
                  }
                }

                onCursorRectangleChanged: ensureCursorVisible()
                onTextChanged: {
                  root.markDirty()
                  Qt.callLater(ensureCursorVisible)
                }

                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    root.close()
                    event.accepted = true
                    return
                  }
                  if ((event.key === Qt.Key_S || event.key === Qt.Key_Enter)
                      && (event.modifiers & Qt.ControlModifier)) {
                    root.saveNote()
                    event.accepted = true
                  }
                }
              }
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: root.moveNotice !== "" ? root.moveNotice
                  : root.movingNote ? "Moving note…"
                  : root.saveFailedState ? "Save failed"
                  : root.dirty ? "Unsaved changes"
                  : root.justSaved ? "Saved"
                  : "Ctrl+S to save"
                color: root.moveNotice !== "" ? (bar ? bar.accent : Color.accent)
                  : root.saveFailedState ? root.urgent
                  : (root.dirty ? root.fg : root.dim)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Button {
                id: saveButton
                text: "Save"
                enabled: root.dirty && !root.loadingNote && !root.noteMissing
                bordered: true
                foreground: root.fg
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.saveNote()
              }
            }
          }

          // ---------- Footer ----------
          PanelSeparator {
            foreground: root.fg
          }

          RowLayout {
            visible: root.vaultConfigured
            width: parent.width
            spacing: Style.space(8)

            Text {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              text: root.vaultPath !== "" ? root.vaultPath : "Detected · " + root.detectedVault
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
            }

            Button {
              id: changeButton
              visible: root.vaultPath !== "" && !root.editingVaultPath
              text: "Change"
              bordered: true
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.startVaultEdit()
            }
          }
        }
      }
    }
  }
}
