pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "danglenoir.hanzi"
  manageIpc: false

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var snapshot: stats.snapshot || ({})
  readonly property bool dataReady: snapshot.ok === true
  readonly property string character: dataReady ? remoteText(snapshot.character) : ""
  readonly property string pinyin: dataReady ? remoteText(snapshot.pinyin) : ""
  readonly property string meaning: dataReady ? remoteText(snapshot.meaning) : ""
  readonly property var components: dataReady && Array.isArray(snapshot.components) ? snapshot.components : []
  readonly property var words: dataReady && Array.isArray(snapshot.words) ? snapshot.words : []
  readonly property string hskLabel: dataReady ? remoteText(snapshot.hskLabel) : ""
  readonly property string mark: "汉字"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function remoteText(value) {
    var text = String(value == null ? "" : value)
    text = text.replace(/<[^>]*>/g, "").replace(/[<>]/g, "")
    text = text.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "")
    text = text.replace(/[\u202A-\u202E\u2066-\u2069]/g, "")
    if (text.length > 200)
      text = text.substring(0, 200)
    return text
  }

  function barTooltip() {
    if (!dataReady) {
      if (stats.loading) return "Loading today's hanzi..."
      return snapshot.error ? remoteText(snapshot.error) : "Today's hanzi is unavailable."
    }
    var line = character
    if (pinyin) line += "  " + pinyin
    if (meaning) line += "  —  " + meaning
    return line
  }

  function heroTitle() {
    if (!dataReady) return "Daily Hanzi"
    if (character && pinyin) return character + "  " + pinyin
    return character || pinyin || "Daily Hanzi"
  }

  function copyCharacter() {
    if (!character) return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(character) + " | wl-copy"])
  }

  function openDictionary() {
    var url = remoteText(snapshot.dictionaryUrl)
    if (url.indexOf("https://www.mdbg.net/") === 0)
      Qt.openUrlExternally(url)
  }

  function refresh(shuffle) {
    stats.refresh(shuffle === true)
  }

  onOpenedChanged: if (opened) refresh(false)

  HanziService {
    id: stats
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.mark
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 0
    verticalPadding: 0
    tooltipText: root.barTooltip()
    fixedWidth: root.vertical
      ? (root.bar ? root.bar.barSize : Style.bar.sizeVertical)
      : Math.max(Style.space(52), horizontalContent.implicitWidth + Style.space(17))
    fixedHeight: root.vertical ? verticalContent.implicitHeight + Style.space(12) : -1

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.refresh(true)
      else root.toggle()
    }

    Row {
      id: horizontalContent
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: Style.space(2)

      Text {
        text: root.mark
        textFormat: Text.PlainText
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    Column {
      id: verticalContent
      visible: root.vertical
      anchors.centerIn: parent
      spacing: Style.space(1)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "汉"
        textFormat: Text.PlainText
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "字"
        textFormat: Text.PlainText
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(400))
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.refresh(true)
        else if (text === "c" || text === "C") root.copyCharacter()
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: parent.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: root.heroTitle()
            meta: root.dataReady ? root.meaning : "Daily character"
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Item {
              width: Style.space(42)
              height: Style.space(42)

              Text {
                anchors.centerIn: parent
                text: root.character || "?"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.space(36)
                font.bold: true
              }
            }

            trailingControl: Component {
              Row {
                id: heroActions
                width: implicitWidth
                spacing: Style.space(6)

                Item {
                  id: hskBadge
                  visible: root.hskLabel !== ""
                  width: visible ? hskPill.implicitWidth : 0
                  height: Math.max(
                    hskPill.implicitHeight,
                    copyButton.implicitHeight,
                    refreshButton.implicitHeight)

                  BorderSurface {
                    id: hskPill
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: hskText.implicitWidth + Style.space(10)
                    implicitHeight: hskText.implicitHeight + Style.space(4)
                    color: "transparent"
                    borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
                    radius: Style.cornerRadius

                    Text {
                      id: hskText
                      anchors.centerIn: parent
                      text: root.hskLabel
                      textFormat: Text.PlainText
                      color: Qt.darker(root.foreground, 1.4)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }
                  }
                }

                PanelActionButton {
                  id: copyButton
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰆏"
                  tooltipText: "Copy " + (root.character || "character")
                  foreground: root.foreground
                  enabled: root.dataReady && !stats.loading
                  focusable: true
                  onClicked: root.copyCharacter()
                }

                PanelActionButton {
                  id: refreshButton
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰑐"
                  tooltipText: "Show a new hanzi"
                  foreground: root.foreground
                  enabled: !stats.loading
                  focusable: true
                  onClicked: root.refresh(true)
                }
              }
            }
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          Column {
            width: parent.width
            visible: !root.dataReady
            spacing: Style.space(7)

            Text {
              width: parent.width
              text: stats.loading ? "Loading today's hanzi..." : "Today's hanzi is unavailable"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              visible: !stats.loading
              text: remoteText(root.snapshot.error) || "Check your network connection and try again."
              textFormat: Text.PlainText
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
          }

          Column {
            width: parent.width
            visible: root.dataReady
            spacing: Style.space(12)

            Column {
              width: parent.width
              visible: root.components.length > 0
              spacing: Style.space(7)

              PanelSectionHeader {
                width: parent.width
                text: "Components"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: root.components

                delegate: Row {
                  required property var modelData
                  width: contentColumn.width
                  spacing: Style.space(10)

                  Text {
                    width: Style.space(28)
                    text: root.remoteText(modelData.character)
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }

                  Column {
                    width: Math.max(0, parent.width - parent.spacing - parent.children[0].width)
                    spacing: Style.space(1)

                    Text {
                      width: parent.width
                      visible: root.remoteText(modelData.pinyin) !== ""
                      text: root.remoteText(modelData.pinyin)
                      textFormat: Text.PlainText
                      color: Qt.darker(root.foreground, 1.45)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }

                    Text {
                      width: parent.width
                      text: root.remoteText(modelData.meaning) || "No gloss in Wiktionary"
                      textFormat: Text.PlainText
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      wrapMode: Text.WordWrap
                    }
                  }
                }
              }
            }

            Column {
              width: parent.width
              visible: root.words.length > 0
              spacing: Style.space(7)

              PanelSectionHeader {
                width: parent.width
                text: "Words"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: root.words

                delegate: Column {
                  required property var modelData
                  width: contentColumn.width
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    text: root.remoteText(modelData.word)
                      + (root.remoteText(modelData.pinyin) ? "  " + root.remoteText(modelData.pinyin) : "")
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    wrapMode: Text.WordWrap
                  }

                  Text {
                    width: parent.width
                    text: root.remoteText(modelData.meaning)
                    textFormat: Text.PlainText
                    color: Qt.darker(root.foreground, 1.45)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: Text.WordWrap
                  }
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(7)

              PanelSectionHeader {
                width: parent.width
                text: "Details"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Text {
                width: parent.width
                visible: root.snapshot.strokes !== "" && root.snapshot.strokes !== undefined && root.snapshot.strokes !== null
                text: "Strokes  " + root.remoteText(root.snapshot.strokes)
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                width: parent.width
                visible: root.remoteText(root.snapshot.radical) !== ""
                text: "Radical  " + root.remoteText(root.snapshot.radical)
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                width: parent.width
                visible: root.remoteText(root.snapshot.traditional) !== ""
                  && root.remoteText(root.snapshot.traditional) !== root.character
                text: "Traditional  " + root.remoteText(root.snapshot.traditional)
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                width: parent.width
                visible: root.remoteText(root.snapshot.etymology) !== ""
                text: root.remoteText(root.snapshot.etymology)
                textFormat: Text.PlainText
                color: Qt.darker(root.foreground, 1.45)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }
            }

            Text {
              width: parent.width
              visible: root.snapshot.stale === true
              text: "Showing cached data. "
                + (remoteText(root.snapshot.error) || "Wiktionary is temporarily unavailable.")
              textFormat: Text.PlainText
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Button {
              visible: remoteText(root.snapshot.dictionaryUrl).indexOf("https://www.mdbg.net/") === 0
              text: "Look up " + (root.character || "this hanzi") + " on MDBG"
              foreground: root.foreground
              fontFamily: root.fontFamily
              focusable: true
              bordered: true
              onClicked: root.openDictionary()
            }
          }
        }
      }
    }
  }
}
