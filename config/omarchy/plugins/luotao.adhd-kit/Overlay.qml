import QtQuick
import "views"
import "Safe.js" as Safe

// Overlay entry point and view dispatcher. One plugin gets one overlay slot,
// so this routes the summon payload to a view:
//
//   omarchy-shell shell summon luotao.adhd-kit '{}'                 -> quick capture
//   omarchy-shell shell summon luotao.adhd-kit '{"view": "timer"}'  -> fullscreen big timer
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property bool opened: capture.opened || bigTimer.opened

  function open(payloadJson) {
    // A summon payload is a handful of keys; anything larger came from
    // something other than a keybinding and is not worth parsing.
    var payload = ({})
    try {
      payload = JSON.parse(Safe.capDocument(payloadJson, Safe.LIMITS.payload) || "{}")
    } catch (e) {
      payload = ({})
    }
    if (!payload || typeof payload !== "object") payload = ({})
    if (payload.view === "timer") {
      capture.close()
      bigTimer.openView(payload)
    } else {
      bigTimer.close()
      capture.openView(payload)
    }
  }

  function close() {
    capture.close()
    bigTimer.close()
  }

  function dismiss() {
    close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "luotao.adhd-kit")
  }

  function toggle() {
    if (opened) dismiss()
    else open("{}")
  }

  CaptureView {
    id: capture
    onDismissRequested: root.dismiss()
  }

  BigTimerView {
    id: bigTimer
    onDismissRequested: root.dismiss()
  }
}
