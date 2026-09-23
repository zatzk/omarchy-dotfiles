import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "ozymandias.menu"

  property FileView themeNameFile: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onLoaded: {
      isWindowsXP = text().trim() === "windows-xp"
    }
    onFileChanged: {
      reload()
    }
  }
  property bool isWindowsXP: false

  implicitWidth: isWindowsXP ? startButton.width : defaultButton.implicitWidth
  implicitHeight: isWindowsXP ? startButton.height : defaultButton.implicitHeight

  // Default Omarchy menu button
  WidgetButton {
    id: defaultButton
    anchors.fill: parent
    bar: root.bar
    visible: !root.isWindowsXP
    text: "\ue900"
    fontFamily: "omarchy"
    horizontalMargin: 7.5
    onPressed: function(btn) {
      if (!root.bar) return
      if (btn === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("omarchy-shell shell toggle ozymandias.menu '{\"menu\":\"root\"}'")
    }
  }

  // Windows XP Start Button
  Rectangle {
    id: startButton
    visible: root.isWindowsXP
    width: Style.space(80)
    height: root.barSize - Style.space(4)
    anchors.centerIn: parent
    radius: 4

    // Iconic green gradient for XP Start Button
    gradient: Gradient {
      GradientStop { 
        position: 0.0
        color: startMouse.containsMouse ? "#4ebf4e" : "#3c9c3c"
      }
      GradientStop { 
        position: 0.5
        color: startMouse.containsMouse ? "#3aa83a" : "#2e842e"
      }
      GradientStop { 
        position: 1.0
        color: startMouse.containsMouse ? "#206220" : "#1a521a"
      }
    }

    border.color: "#164416"
    border.width: 1

    Row {
      anchors.centerIn: parent
      spacing: Style.space(4)

      Text {
        text: "start"
        color: "#ffffff"
        font.family: "Tahoma"
        font.pixelSize: Style.font.title
        font.bold: true
        font.italic: true
        renderType: Text.NativeRendering
      }
    }

    MouseArea {
      id: startMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function(mouse) {
        if (!root.bar) return
        if (mouse.button === Qt.RightButton) {
          root.bar.run("xdg-terminal-exec")
        } else {
          root.bar.run("omarchy-shell shell toggle ozymandias.menu '{\"menu\":\"root\"}'")
        }
      }
    }
  }
}
