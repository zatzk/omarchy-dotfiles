import Quickshell
import Quickshell.Io
import QtQuick

// Why this plugin reads its state and config files through `head -c` instead
// of FileView, and why the FileView that remains needs *both* `preload: false`
// and `blockAllReads: true`.
//
// Run it against a deliberately huge file:
//
//   head -c $((300 * 1024 * 1024)) /dev/zero | tr '\0' x > /tmp/huge.json
//   PROBE_FILE=/tmp/huge.json qs -p test/fileview-probe.qml
//
// Expected output: `retained chars: 65537` (one byte past the 64 KiB cap, which
// is what Safe.capDocument() then refuses) and one `fileChanged` from the touch
// this probe performs. Sample the process's memory while it runs
// (`awk '/^Private_(Clean|Dirty)/{s+=$2} END{print s}' /proc/<pid>/smaps_rollup`)
// and it stays at the empty-shell baseline — measured 66 MB here against a
// 70 MB baseline.
//
// Two variants that look equivalent and are not, both measured against the same
// 300 MB file on Quickshell's FileView:
//
//   * `text()` on a plain FileView       -> retained 314572800 chars, 976 MB
//   * `blockAllReads` without `preload:false` -> retained 65537 chars from the
//     helper, but still 976 MB, because assigning `path` starts a full eager
//     read before `blockAllReads` reaches the C++ side. A shell started with an
//     already-oversized file pays that cost once, silently.
//
// So the notifier below asserts nothing about caps in JS: it simply never reads.
ShellRoot {
  id: root

  readonly property string file: Quickshell.env("PROBE_FILE")
  readonly property int cap: 64 * 1024
  property int changes: 0

  Process {
    id: reader
    running: true
    command: ["head", "-c", String(root.cap + 1), "--", root.file]
    stdout: StdioCollector {
      onStreamFinished: console.log("probe: retained chars: " + this.text.length)
    }
    stderr: StdioCollector {}
  }

  FileView {
    path: root.file
    watchChanges: true
    preload: false
    blockAllReads: true
    printErrors: false
    onFileChanged: {
      root.changes++
      console.log("probe: fileChanged #" + root.changes)
      reader.running = false
      reader.running = true
    }
  }

  Process { id: toucher; command: ["touch", "--", root.file] }

  Timer { running: true; interval: 2000; onTriggered: toucher.running = true }
  Timer {
    running: true
    interval: 5000
    onTriggered: {
      console.log("probe: done, changes=" + root.changes)
      Qt.quit()
    }
  }
}
