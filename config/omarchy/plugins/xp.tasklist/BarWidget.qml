import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "xp.tasklist"

  property var toplevelsList: []

  function updateToplevels() {
    var rawList = Hyprland.toplevels.values || [];
    var filtered = [];
    var currentWs = Hyprland.focusedWorkspace;
    if (!currentWs) return;

    for (var i = 0; i < rawList.length; i++) {
      var t = rawList[i];
      if (t.workspace && t.workspace.id === currentWs.id) {
        filtered.push(t);
      }
    }
    toplevelsList = filtered;
  }

  Component.onCompleted: updateToplevels()

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { updateToplevels() }
  }

  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() { updateToplevels() }
  }

  readonly property var activeToplevel: ToplevelManager.activeToplevel

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() { updateToplevels() }
  }

  implicitWidth: layout.implicitWidth
  implicitHeight: barSize

  Row {
    id: layout
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)

    Repeater {
      model: root.toplevelsList

      Rectangle {
        required property var modelData
        readonly property var toplevel: modelData
        readonly property bool isActive: root.activeToplevel !== null && root.activeToplevel.address === toplevel.address

        width: isActive ? Style.space(180) : Style.space(130)
        height: root.barSize - Style.space(4)
        radius: 3

        Behavior on width {
          NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        // Classic Windows XP taskbar button gradient
        gradient: Gradient {
          GradientStop {
            position: 0.0
            color: isActive ? "#1542b3" : (mouseArea.containsMouse ? "#558cec" : "#3878ec")
          }
          GradientStop {
            position: 1.0
            color: isActive ? "#1a50db" : (mouseArea.containsMouse ? "#2058d2" : "#1644b8")
          }
        }

        border.color: isActive ? "#122a7f" : "#0e3a9c"
        border.width: 1

        MouseArea {
          id: mouseArea
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
              if (root.bar) root.bar.run("hyprctl dispatch focuswindow address:" + toplevel.address);
            } else if (mouse.button === Qt.RightButton) {
              if (root.bar) root.bar.run("hyprctl dispatch closewindow address:" + toplevel.address);
            }
          }
        }

        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.space(6)
          anchors.rightMargin: Style.space(6)
          spacing: Style.space(4)

          Image {
            id: appIcon
            width: Style.space(16)
            height: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            source: {
              var appId = toplevel.wayland ? toplevel.wayland.appId : "";
              if (!appId && toplevel.lastIpcObject) appId = toplevel.lastIpcObject.class;
              if (!appId) return Quickshell.iconPath("application-x-executable", true);
              var path = Quickshell.iconPath(appId.toLowerCase(), true);
              return path ? path : Quickshell.iconPath("application-x-executable", true);
            }
            fillMode: Image.PreserveAspectFit
          }

          Text {
            id: titleText
            width: parent.width - appIcon.width - parent.spacing - Style.space(12) - (isActive ? Style.space(56) : 0)
            anchors.verticalCenter: parent.verticalCenter
            text: toplevel.title || "Window"
            color: "#ffffff"
            font.family: "Tahoma"
            font.pixelSize: Style.font.bodySmall
            font.bold: isActive
            elide: Text.ElideRight
            renderType: Text.NativeRendering
          }

          // Close, Maximize, Minimize Buttons for the Active Window
          Row {
            visible: isActive
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            // Minimize Button
            Rectangle {
              width: Style.space(15)
              height: Style.space(15)
              radius: 1
              color: minMouse.pressed ? "#001b5f" : (minMouse.containsMouse ? "#548beb" : "#3878ec")
              border.color: "#ffffff"
              border.width: 1

              Text {
                text: "—"
                color: "#ffffff"
                font.pixelSize: Style.font.caption
                anchors.centerIn: parent
                font.bold: true
              }

              MouseArea {
                id: minMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                  if (root.bar) {
                    root.bar.run("hyprctl dispatch togglefloating active");
                  }
                }
              }
            }

            // Maximize Button
            Rectangle {
              width: Style.space(15)
              height: Style.space(15)
              radius: 1
              color: maxMouse.pressed ? "#001b5f" : (maxMouse.containsMouse ? "#548beb" : "#3878ec")
              border.color: "#ffffff"
              border.width: 1

              Text {
                text: "□"
                color: "#ffffff"
                font.pixelSize: Style.font.caption
                anchors.centerIn: parent
                font.bold: true
              }

              MouseArea {
                id: maxMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                  if (root.bar) {
                    root.bar.run("hyprctl dispatch fullscreen 1");
                  }
                }
              }
            }

            // Close Button
            Rectangle {
              width: Style.space(15)
              height: Style.space(15)
              radius: 1
              color: closeMouse.pressed ? "#aa1500" : (closeMouse.containsMouse ? "#ff6347" : "#e04324")
              border.color: "#ffffff"
              border.width: 1

              Text {
                text: "×"
                color: "#ffffff"
                font.pixelSize: Style.font.title
                anchors.centerIn: parent
                font.bold: true
              }

              MouseArea {
                id: closeMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                  if (root.bar) {
                    root.bar.run("hyprctl dispatch closewindow address:" + toplevel.address);
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
