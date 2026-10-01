import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "ntfy"

  readonly property var ntfy: bar && bar.shell ? bar.shell.serviceFor("ntfy") : null
  readonly property int unread: ntfy ? ntfy.unreadCount : 0
  readonly property var messages: ntfy ? ntfy.messages : []

  property bool popupOpen: false

  function close() { popupOpen = false }

  function relativeTime(epoch) {
    var s = Math.max(0, Math.floor(Date.now() / 1000) - epoch)
    if (s < 60) return "now"
    if (s < 3600) return Math.floor(s / 60) + "m"
    if (s < 86400) return Math.floor(s / 3600) + "h"
    return Math.floor(s / 86400) + "d"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: barSize

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.unread > 0 ? "󰂞" : (root.ntfy && root.ntfy.connected ? "󰂚" : "󰂛")
    active: root.unread > 0
    tooltipText: !root.ntfy ? "ntfy service not loaded"
      : (root.unread > 0 ? root.unread + " unread · " : "") + root.ntfy.status
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        if (root.ntfy) root.ntfy.markAllRead()
        return
      }
      root.popupOpen = !root.popupOpen
    }
  }

  // Opening the popup counts as reading what's in it.
  onPopupOpenChanged: if (!popupOpen && ntfy) ntfy.markAllRead()

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(column.implicitHeight, Style.space(480))

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(8)

      Row {
        width: parent.width
        spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          text: "ntfy"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          width: parent.width - clearButton.width - Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
        }

        Button {
          id: clearButton
          iconText: "󰎟"
          tooltipText: "Clear all"
          foreground: root.bar.foreground
          visible: root.messages.length > 0
          onClicked: if (root.ntfy) root.ntfy.clearMessages()
        }
      }

      Text {
        textFormat: Text.PlainText
        text: root.ntfy ? root.ntfy.status : "Service not loaded"
        color: Qt.darker(root.bar.foreground, 1.6)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: parent.width
      }

      PanelSeparator { foreground: root.bar.foreground }

      Text {
        visible: root.messages.length === 0
        textFormat: Text.PlainText
        text: root.ntfy && !root.ntfy.configured
          ? "Add topics to ~/.config/omarchy/ntfy.json"
          : "No messages yet"
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        width: parent.width
        wrapMode: Text.Wrap
      }

      Repeater {
        model: root.messages.slice(0, 8)

        BorderSurface {
          id: row
          required property var modelData

          width: column.width
          height: inner.implicitHeight + Style.space(12)
          radius: Style.spacing.labelGap
          color: !modelData.read ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"
          borderSpec: modelData.priority >= 4
            ? Border.controlSpec("normal", root.bar.foreground, root.bar.urgent) : Border.none()

          Column {
            id: inner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(2)

            Row {
              width: parent.width
              spacing: Style.space(6)

              Text {
                textFormat: Text.PlainText
                text: (row.modelData.emoji ? row.modelData.emoji + " " : "") + (row.modelData.title || row.modelData.topic)
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                elide: Text.ElideRight
                width: parent.width - meta.implicitWidth - Style.space(6)
              }

              Text {
                id: meta
                textFormat: Text.PlainText
                text: (row.modelData.title ? row.modelData.topic + " · " : "") + root.relativeTime(row.modelData.time)
                color: Qt.darker(root.bar.foreground, 1.6)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              textFormat: Text.PlainText
              text: row.modelData.message
              color: Qt.darker(root.bar.foreground, 1.2)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
              maximumLineCount: 4
              elide: Text.ElideRight
              width: parent.width
            }
          }

          MouseArea {
            anchors.fill: parent
            enabled: row.modelData.click !== ""
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.ntfy.openMessage(row.modelData)
              root.popupOpen = false
            }
          }
        }
      }
    }
  }
}
