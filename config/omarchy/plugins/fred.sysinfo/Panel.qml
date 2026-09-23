import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Ui
import qs.Commons
import "SysinfoStore.js" as SysinfoStore

Panel {
  id: root
  moduleName: "fred.sysinfo"
  ipcTarget: "fred.sysinfo"
  manageIpc: false

  readonly property string pluginVersion: "1.1.2"

  property var stats: ({})
  property int phraseIndex: 0
  property string activeProfile: "performance"
  readonly property var activePhrases: [
    "Crunching numbers",
    "Herding cores",
    "Chilling silicon",
    "Pumping cycles",
    "Dispatching threads",
    "Wrangling watts",
    "Polling sensors",
    "Synthesizing electrons"
  ]
  readonly property string heroStatusText: activePhrases[phraseIndex % activePhrases.length]

  readonly property string probeHelperPath: {
    var resolved = String(Qt.resolvedUrl("sysinfo-probe.py"))
    if (resolved.indexOf("file://") === 0) {
      return decodeURIComponent(resolved.substring(7))
    }
    return Quickshell.env("HOME") + "/.config/omarchy/plugins/fred.sysinfo/sysinfo-probe.py"
  }

  readonly property var processEnv: ({
    "PATH": "/usr/bin:/bin",
    "HOME": Quickshell.env("HOME") || "",
    "LC_ALL": "C.UTF-8",
    "XDG_RUNTIME_DIR": Quickshell.env("XDG_RUNTIME_DIR") || "",
    "XDG_CACHE_HOME": Quickshell.env("XDG_CACHE_HOME") || ""
  })

  function refresh() {
    if (!probeProc.running) {
      probeProc.running = true
    }
  }

  function handleProbeOutput(text) {
    if (!text || text.trim() === "") return
    try {
      var data = JSON.parse(text)
      if (data && typeof data === "object") {
        root.stats = data
        if (data.cpu && data.cpu.power_profile) {
          root.activeProfile = data.cpu.power_profile
        }
        Qt.callLater(function() {
          if (button.tooltipHovered && !root.opened && root.bar) {
            root.bar.showTooltip(button, button.tooltipText)
          }
        })
      }
    } catch (e) {
      console.warn("sysinfo parse error:", e)
    }
  }

  function setProfile(profile) {
    if (!profile || profileProc.running) return
    root.activeProfile = profile
    profileProc.command = ["/usr/bin/powerprofilesctl", "set", profile]
    profileProc.running = true
  }

  function copyToClipboard(value) {
    if (!value) return
    clipProc.command = ["sh", "-c", "printf '%s' \"$1\" | wl-copy", "_", String(value)]
    clipProc.running = true
  }

  function launchSystemMonitor() {
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("omarchy-launch-terminal btop")
    } else {
      Util.execDetached("omarchy-launch-terminal btop")
    }
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
    }
  }

  readonly property var myWindow: root.QsWindow ? root.QsWindow.window : null
  readonly property string screenName: (myWindow && myWindow.screen) ? String(myWindow.screen.name || "") : ""
  onScreenNameChanged: {
    if (screenName) SysinfoStore.register(screenName, root)
  }

  Component.onCompleted: {
    refresh()
    Qt.callLater(function() {
      if (root.screenName) SysinfoStore.register(root.screenName, root)
    })
  }

  Component.onDestruction: {
    if (root.screenName) SysinfoStore.unregister(root.screenName, root)
  }

  IpcHandler {
    target: "fred.sysinfo"
    function toggleMonitor(monitor: string): void {
      var cur = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
      SysinfoStore.toggle(monitor, cur)
    }
    function openMonitor(monitor: string): void {
      var cur = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
      SysinfoStore.open(monitor, cur)
    }
    function closeMonitor(monitor: string): void {
      var cur = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
      SysinfoStore.close(monitor, cur)
    }
    function open(): void {
      var cur = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
      SysinfoStore.open("", cur)
    }
    function close(): void {
      var cur = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
      SysinfoStore.close("", cur)
    }
    function show(): void { open() }
    function hide(): void { close() }
    function toggle(): void {
      var cur = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
      SysinfoStore.toggle("", cur)
    }
  }

  Process {
    id: probeProc
    command: [root.probeHelperPath]
    clearEnvironment: true
    environment: root.processEnv

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text && text.length <= 65536) {
          root.handleProbeOutput(text)
        }
      }
      onDataChanged: {
        if (text.length > 65536) {
          probeProc.signal(9)
          probeProc.running = false
        }
      }
    }

    onStarted: probeWatchdog.restart()
    onExited: probeWatchdog.stop()
  }

  Timer {
    id: probeWatchdog
    interval: 3000
    repeat: false
    onTriggered: {
      if (probeProc.running) {
        probeProc.signal(9)
        probeProc.running = false
      }
    }
  }

  Process {
    id: profileProc
    clearEnvironment: true
    environment: root.processEnv
    onExited: root.refresh()
  }

  Process {
    id: clipProc
    clearEnvironment: true
    environment: root.processEnv
  }

  Timer {
    interval: 2500
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: phraseTimer
    interval: 3500
    running: root.opened
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: {
        root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
      }
    }
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍛"
    tooltipText: {
      var prod = (root.stats.system && root.stats.system.product) ? (root.stats.system.vendor + " " + root.stats.system.product) : "System Hardware"
      var cpuUsage = (root.stats.cpu && root.stats.cpu.usage_percent !== undefined && root.stats.cpu.usage_percent !== null) ? root.stats.cpu.usage_percent.toFixed(1) + "%" : "--"
      var ramAvailable = (root.stats.memory && root.stats.memory.avail_gb !== undefined && root.stats.memory.avail_gb !== null) ? root.stats.memory.avail_gb.toFixed(1) + " GB available" : "--"
      var diskFree = (root.stats.storage && root.stats.storage.free_gb !== undefined && root.stats.storage.free_gb !== null) ? root.stats.storage.free_gb.toFixed(1) + " GB free" : "--"
      var resources = "CPU " + cpuUsage + " · RAM " + ramAvailable + " · Disk " + diskFree
      var ver = "fred.sysinfo v" + root.pluginVersion
      return prod + "\n" + resources + "\n\n" + ver
    }
    onTooltipHoveredChanged: {
      if (tooltipHovered && !root.opened) root.refresh()
    }
    onPressed: function(b) { root.toggle() }
  }

  SysinfoPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(580))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) panelFlick.contentY = Math.max(0, Math.min(panelFlick.contentHeight - panelFlick.height, panelFlick.contentY + dy * Style.space(100)))
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: panelColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar {
          policy: panelFlick.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        }

        WheelHandler {
          target: panelFlick
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
          onWheel: function(event) {
            panelFlick.contentY = Math.max(0, Math.min(panelFlick.contentHeight - panelFlick.height, panelFlick.contentY - event.angleDelta.y))
          }
        }

        Column {
          id: panelColumn
          width: panelFlick.width - (panelFlick.interactive ? Style.space(10) : 0)
          spacing: Style.space(6)

          // ---------- Hero: Chip Icon · Title / Status · Pill ----------
          Item {
            id: heroItem
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroBadge.implicitHeight)

            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: "󰍛"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.displayLarge
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(12)
              anchors.right: heroBadge.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                text: (root.stats.system && root.stats.system.product) ? (root.stats.system.vendor + " " + root.stats.system.product) : "System Hardware"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                id: heroStatus
                textFormat: Text.PlainText
                text: root.heroStatusText.toUpperCase()
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
              }
            }

            BorderSurface {
              id: heroBadge
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              implicitWidth: heroBadgeText.implicitWidth + Style.space(12)
              implicitHeight: heroBadgeText.implicitHeight + Style.space(6)
              color: "transparent"
              borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)
              radius: Style.cornerRadius

              Text {
                id: heroBadgeText
                anchors.centerIn: parent
                text: (root.stats.cpu && root.stats.cpu.temp_c ? root.stats.cpu.temp_c.toFixed(1) + "°C · " : "") + (root.stats.cpu && root.stats.cpu.avg_freq_mhz ? (root.stats.cpu.avg_freq_mhz / 1000).toFixed(1) + " GHz" : (root.stats.cpu ? root.stats.cpu.topology : "--"))
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }
          }

          // ---------- Section 1: Processor ----------
          PanelSeparator { foreground: root.bar.foreground }

          PanelSectionHeader {
            text: "PROCESSOR (CPU)"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(20)

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(3)

              InfoPair { label: "Model"; value: root.stats.cpu ? root.stats.cpu.model : "--" }
              InfoPair { label: "Topology"; value: root.stats.cpu ? root.stats.cpu.topology : "--" }
              InfoPair {
                label: "Frequency";
                value: root.stats.cpu && root.stats.cpu.avg_freq_mhz ? (root.stats.cpu.avg_freq_mhz / 1000).toFixed(2) + " GHz" : "--"
              }
              InfoPair {
                label: "Freq Limits";
                value: root.stats.cpu && root.stats.cpu.min_limit_mhz ? ((root.stats.cpu.min_limit_mhz / 1000).toFixed(2) + " – " + (root.stats.cpu.max_limit_mhz / 1000).toFixed(2) + " GHz") : "--"
              }
            }

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(3)

              InfoPair {
                label: "CPU Usage";
                value: root.stats.cpu && root.stats.cpu.usage_percent !== undefined ? root.stats.cpu.usage_percent + "%" : "--";
                valueColor: root.stats.cpu && root.stats.cpu.usage_percent > 85 ? root.bar.urgent : root.bar.foreground
              }
              InfoPair { label: "Load Avg"; value: root.stats.cpu ? root.stats.cpu.load_avg : "--" }
              InfoPair { label: "Governor"; value: root.stats.cpu ? root.stats.cpu.governor : "--" }
              InfoPair { label: "Cache"; value: root.stats.cpu ? root.stats.cpu.cache : "--" }
            }
          }

          // Power Profiles
          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(6)

            readonly property var profiles: ["power-saver", "balanced", "performance"]
            readonly property real cellWidth: (width - spacing * 2) / 3

            Repeater {
              model: profileRow.profiles
              Button {
                required property var modelData
                required property int index
                width: profileRow.cellWidth
                iconText: modelData === "power-saver" ? "󰌪" : (modelData === "balanced" ? "󰊚" : "󰓅")
                iconSize: Style.font.title
                text: modelData === "power-saver" ? "Saver" : (modelData === "balanced" ? "Balanced" : "Performance")
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.space(4)
                bordered: true
                active: root.activeProfile === modelData
                onClicked: root.setProfile(modelData)
              }
            }
          }

          // ---------- Section 2: Thermal Sensors ----------
          PanelSeparator { foreground: root.bar.foreground }

          PanelSectionHeader {
            text: "THERMAL SENSORS & POWER"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(20)

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(3)

              InfoPair {
                label: "CPU Temp";
                value: root.stats.temperatures && root.stats.temperatures.cpu !== null ? root.stats.temperatures.cpu.toFixed(1) + "°C" : "--";
                valueColor: root.stats.temperatures && root.stats.temperatures.cpu > 80 ? root.bar.urgent : root.bar.foreground
              }
              InfoPair {
                label: "NVMe Drive";
                value: root.stats.temperatures && root.stats.temperatures.nvme !== null ? root.stats.temperatures.nvme.toFixed(1) + "°C" : "--"
              }
              InfoPair {
                label: "LAN 1";
                value: root.stats.temperatures && root.stats.temperatures.lan1 !== null ? root.stats.temperatures.lan1.toFixed(1) + "°C" : "--"
              }
              InfoPair {
                label: "GPU Power";
                value: root.stats.gpu && root.stats.gpu.power_w !== null ? root.stats.gpu.power_w.toFixed(1) + " W" : "--"
              }
            }

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(3)

              InfoPair {
                label: "GPU Temp";
                value: root.stats.temperatures && root.stats.temperatures.gpu !== null ? root.stats.temperatures.gpu.toFixed(1) + "°C" : "--"
              }
              InfoPair {
                label: "Wi-Fi";
                value: root.stats.temperatures && root.stats.temperatures.wifi !== null ? root.stats.temperatures.wifi.toFixed(1) + "°C" : "--"
              }
              InfoPair {
                label: "LAN 2";
                value: root.stats.temperatures && root.stats.temperatures.lan2 !== null ? root.stats.temperatures.lan2.toFixed(1) + "°C" : "--"
              }
              InfoPair {
                label: "GPU Clock";
                value: root.stats.gpu && root.stats.gpu.clock_mhz !== null ? (root.stats.gpu.clock_mhz + " MHz" + (root.stats.gpu.voltage_v ? " (" + root.stats.gpu.voltage_v.toFixed(2) + "V)" : "")) : "--"
              }
            }
          }

          // ---------- Section 3: Motherboard & System ----------
          PanelSeparator { foreground: root.bar.foreground }

          PanelSectionHeader {
            text: "MOTHERBOARD & FIRMWARE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(20)

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(3)

              InfoPair { label: "Motherboard"; value: root.stats.system ? root.stats.system.board : "--" }
              InfoPair { label: "Chassis"; value: root.stats.system ? root.stats.system.chassis : "--" }
              InfoPair { label: "Kernel"; value: root.stats.system ? root.stats.system.kernel : "--" }
            }

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(3)

              InfoPair {
                label: "BIOS";
                value: root.stats.system ? (root.stats.system.bios_version + (root.stats.system.bios_date ? " (" + root.stats.system.bios_date + ")" : "")) : "--"
              }
              InfoPair { label: "EC Firmware"; value: root.stats.system ? root.stats.system.ec_version : "--" }
              InfoPair { label: "System Uptime"; value: root.stats.system ? root.stats.system.uptime : "--" }
            }
          }

          // ---------- Section 4: Memory & Storage ----------
          PanelSeparator { foreground: root.bar.foreground }

          PanelSectionHeader {
            text: "MEMORY & STORAGE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(20)

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(3)

              InfoPair {
                label: "RAM In-Use";
                value: root.stats.memory ? (root.stats.memory.used_gb + " / " + root.stats.memory.total_gb + " GB (" + Math.round(root.stats.memory.used_percent) + "%)") : "--"
              }
              InfoPair { label: "RAM Avail"; value: root.stats.memory ? (root.stats.memory.avail_gb + " GB") : "--" }
              InfoPair { label: "Drive Model"; value: root.stats.storage ? root.stats.storage.model : "--" }
            }

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(3)

              InfoPair {
                label: "ZRAM / Swap";
                value: root.stats.memory ? (root.stats.memory.swap_used_gb + " / " + root.stats.memory.swap_total_gb + " GB") : "--"
              }
              InfoPair {
                label: "Root (/)";
                value: root.stats.storage ? (root.stats.storage.used_gb + " / " + root.stats.storage.total_gb + " GB (" + Math.round(root.stats.storage.used_percent) + "%)") : "--"
              }
              InfoPair {
                label: "Free Disk";
                value: root.stats.storage ? (root.stats.storage.free_gb + " GB free") : "--"
              }
            }
          }

          // ---------- Section 5: I/O & Bus Controllers ----------
          PanelSeparator { foreground: root.bar.foreground }

          PanelSectionHeader {
            text: "I/O & BUS CONTROLLERS"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(20)

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(3)

              InfoPair { label: "Ethernet"; value: root.stats.io ? root.stats.io.ethernet : "--" }
              InfoPair { label: "Wireless"; value: root.stats.io ? root.stats.io.wifi : "--" }
            }

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(3)

              InfoPair { label: "Graphics"; value: root.stats.io ? root.stats.io.graphics : "--" }
              InfoPair { label: "HD Audio"; value: root.stats.io ? root.stats.io.audio : "--" }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)
            visible: !!(root.stats.io && root.stats.io.usb_peripherals && root.stats.io.usb_peripherals.length > 0)

            InfoLabel {
              text: "Connected USB"
              anchors.verticalCenter: parent.verticalCenter
            }
            Item {
              width: Math.max(0, parent.width - parent.children[0].implicitWidth - usbVal.implicitWidth - parent.spacing * 2)
              height: 1
              anchors.verticalCenter: parent.verticalCenter
            }
            DetailValue {
              id: usbVal
              text: root.stats.io && root.stats.io.usb_peripherals ? root.stats.io.usb_peripherals.join(", ") : "--"
              width: Math.min(implicitWidth, Math.max(Style.space(40), parent.width - parent.children[0].implicitWidth - parent.spacing * 2))
              elide: Text.ElideRight
              anchors.verticalCenter: parent.verticalCenter
              tooltipText: root.stats.io && root.stats.io.usb_peripherals ? root.stats.io.usb_peripherals.join("\n") : ""
            }
          }

          // ---------- Section 6: Action Footer ----------
          PanelSeparator { foreground: root.bar.foreground }

          Button {
            width: parent.width
            iconText: "󰒋"
            iconSize: Style.font.title
            text: "Open System Monitor (btop)"
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.space(5)
            bordered: true
            onClicked: {
              root.launchSystemMonitor()
              root.close()
            }
          }

          // ---------- Section 7: Version Footer ----------
          Item {
            width: parent.width
            height: Style.space(22)

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "fred.sysinfo v" + root.pluginVersion
              color: root.bar.foreground
              opacity: 0.45
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }

  component InfoPair: Row {
    id: pairRow
    property string label: ""
    property string value: ""
    property color valueColor: root.bar.foreground
    property bool copyable: true

    width: parent.width
    spacing: Style.space(8)

    InfoLabel {
      id: pairLabel
      text: pairRow.label
      anchors.verticalCenter: parent.verticalCenter
    }
    Item {
      width: Math.max(0, pairRow.width - pairLabel.implicitWidth - pairValue.implicitWidth - pairRow.spacing * 2)
      height: 1
      anchors.verticalCenter: parent.verticalCenter
    }
    DetailValue {
      id: pairValue
      text: pairRow.value
      color: pairRow.valueColor
      copyable: pairRow.copyable
      width: Math.min(implicitWidth, Math.max(Style.space(40), pairRow.width - pairLabel.implicitWidth - pairRow.spacing * 2))
      elide: Text.ElideRight
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component DetailValue: InfoValue {
    property bool copyable: true
    property string tooltipText: "Click to copy"

    horizontalAlignment: Text.AlignRight
    elide: Text.ElideRight

    MouseArea {
      id: valueMouse
      anchors.fill: parent
      enabled: parent.copyable && parent.text !== "" && parent.text !== "--"
      hoverEnabled: enabled
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.copyToClipboard(parent.text)
    }

    PanelToolTip {
      visible: valueMouse.enabled && valueMouse.containsMouse
      text: tooltipText
      fontFamily: root.bar.fontFamily
    }
  }
}
