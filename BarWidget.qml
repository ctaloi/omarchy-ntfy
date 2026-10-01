import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "ntfy"

  readonly property string allFilter: "__all"
  readonly property string unreadFilter: "__unread"

  readonly property var ntfy: bar && bar.shell ? bar.shell.serviceFor("ntfy") : null
  readonly property int unread: ntfy ? ntfy.unreadCount : 0
  readonly property var messages: ntfy ? ntfy.messages : []
  readonly property var topics: ntfy ? ntfy.topics : []
  readonly property var unreadByTopic: ntfy ? ntfy.unreadByTopic : ({})

  // Lives on the service so the choice survives closing the panel and is
  // shared by the bar on every monitor.
  readonly property string filter: {
    var f = ntfy ? ntfy.viewFilter : allFilter
    if (f !== allFilter && f !== unreadFilter && topics.indexOf(f) === -1) return allFilter
    return f
  }
  readonly property bool topicFiltered: filter !== allFilter && filter !== unreadFilter
  readonly property var visibleMessages: messages.filter(function(m) {
    if (filter === unreadFilter) return !m.read
    if (topicFiltered) return m.topic === filter
    return true
  })
  readonly property string sendTopic: topicFiltered ? filter : (sendPicker.value || (topics.length > 0 ? topics[0] : ""))

  readonly property var filterOptions: {
    var opts = [
      { value: allFilter, label: "All messages" + (messages.length ? "  (" + messages.length + ")" : "") },
      { value: unreadFilter, label: "Unread" + (unread ? "  (" + unread + ")" : "") }
    ]
    for (var i = 0; i < topics.length; i++) {
      var n = unreadByTopic[topics[i]] || 0
      opts.push({ value: topics[i], label: topics[i] + (n ? "  (" + n + ")" : "") })
    }
    return opts
  }

  readonly property string tooltip: {
    if (!ntfy) return "ntfy service not loaded"
    if (unread === 0) return ntfy.status
    var busiest = Object.keys(unreadByTopic).sort(function(a, b) { return unreadByTopic[b] - unreadByTopic[a] })
    var parts = busiest.slice(0, 3).map(function(t) { return t + " " + unreadByTopic[t] })
    if (busiest.length > 3) parts.push("+" + (busiest.length - 3) + " more")
    return unread + " unread — " + parts.join(", ")
  }

  property bool popupOpen: false

  function close() { popupOpen = false }

  function setFilter(value) {
    if (ntfy) ntfy.viewFilter = value
    filterPicker.value = value
    list.contentY = 0
  }

  function send() {
    var text = sendField.text.trim()
    if (!text || !ntfy || !sendTopic) return
    ntfy.publish(sendTopic, text)
    sendField.text = ""
  }

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
    tooltipText: root.tooltip
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        if (root.ntfy) root.ntfy.markAllRead()
        return
      }
      root.popupOpen = !root.popupOpen
    }
  }

  // Closing the panel marks what it was showing as read: one topic when
  // filtered to a topic, otherwise everything.
  onPopupOpenChanged: if (!popupOpen && ntfy) ntfy.markRead(topicFiltered ? filter : "")

  // `omarchy-shell ntfy toggle` acts on the focused monitor's bar only.
  Connections {
    target: root.ntfy
    function onToggleRequested() {
      var win = root.QsWindow.window
      var focused = Hyprland.focusedMonitor
      if (!win || !win.screen || !focused || win.screen.name === focused.name) root.popupOpen = !root.popupOpen
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    focusTarget: sendField
    contentWidth: popup.fittedContentWidth(Style.space(400))
    contentHeight: popup.fittedContentHeight(column.implicitHeight, Style.space(560))

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(8)

      Row {
        width: parent.width
        spacing: Style.space(4)

        Column {
          width: parent.width - readButton.width - clearButton.width - Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(1)

          Text {
            textFormat: Text.PlainText
            text: "ntfy"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
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
        }

        Button {
          id: readButton
          iconText: "󰸞"
          tooltipText: root.topicFiltered ? "Mark " + root.filter + " read" : "Mark all read"
          foreground: root.bar.foreground
          enabled: root.topicFiltered ? (root.unreadByTopic[root.filter] || 0) > 0 : root.unread > 0
          opacity: enabled ? 1.0 : 0.4
          anchors.verticalCenter: parent.verticalCenter
          onClicked: if (root.ntfy) root.ntfy.markRead(root.topicFiltered ? root.filter : "")
        }

        Button {
          id: clearButton
          iconText: "󰎟"
          tooltipText: root.topicFiltered ? "Clear " + root.filter : "Clear all"
          foreground: root.bar.foreground
          enabled: root.visibleMessages.length > 0 || (!root.topicFiltered && root.messages.length > 0)
          opacity: enabled ? 1.0 : 0.4
          anchors.verticalCenter: parent.verticalCenter
          onClicked: if (root.ntfy) root.ntfy.clearMessages(root.topicFiltered ? root.filter : "")
        }
      }

      Dropdown {
        id: filterPicker
        visible: root.topics.length > 0
        width: parent.width
        showLabel: false
        options: root.filterOptions
        value: root.filter
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        onChanged: function(value) { root.setFilter(value) }
      }

      Text {
        visible: root.visibleMessages.length === 0
        textFormat: Text.PlainText
        text: root.ntfy && !root.ntfy.configured ? "Add topics to ~/.config/omarchy/ntfy.json"
          : root.filter === root.unreadFilter ? "All caught up"
          : root.topicFiltered ? "Nothing on " + root.filter + " yet"
          : "No messages yet"
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        width: parent.width
        wrapMode: Text.Wrap
      }

      Flickable {
        id: list
        visible: root.visibleMessages.length > 0
        width: parent.width
        height: Math.min(listColumn.implicitHeight, Style.space(380))
        contentHeight: listColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: listColumn
          width: list.width
          spacing: Style.space(4)

          Repeater {
            model: root.visibleMessages

            BorderSurface {
              id: row
              required property var modelData

              width: listColumn.width
              height: inner.implicitHeight + Style.space(12)
              radius: Style.spacing.labelGap
              color: !modelData.read ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"
              borderSpec: modelData.priority >= 4
                ? Border.controlSpec("normal", root.bar.foreground, root.bar.urgent) : Border.none()

              MouseArea {
                anchors.fill: parent
                enabled: row.modelData.click !== ""
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.ntfy.openMessage(row.modelData)
                  root.popupOpen = false
                }
              }

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
                    text: (row.modelData.emoji ? row.modelData.emoji + " " : "") + (row.modelData.title || row.modelData.message)
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    elide: Text.ElideRight
                    width: parent.width - when.implicitWidth - Style.space(6)
                  }

                  Text {
                    id: when
                    textFormat: Text.PlainText
                    text: root.relativeTime(row.modelData.time)
                    color: Qt.darker(root.bar.foreground, 1.6)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  visible: row.modelData.title !== ""
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

                // Topic name doubles as a shortcut to filter by it.
                Text {
                  visible: !root.topicFiltered || row.modelData.sent === true
                  textFormat: Text.PlainText
                  text: (root.topicFiltered ? "" : row.modelData.topic) + (row.modelData.sent ? (root.topicFiltered ? "sent" : " · sent") : "")
                  color: topicHover.hovered ? Color.accent : Qt.darker(root.bar.foreground, 1.6)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption

                  HoverHandler { id: topicHover; cursorShape: Qt.PointingHandCursor; enabled: !root.topicFiltered }
                  TapHandler { enabled: !root.topicFiltered; onTapped: root.setFilter(row.modelData.topic) }
                }
              }
            }
          }
        }
      }

      PanelSeparator {
        visible: root.ntfy && root.ntfy.configured
        foreground: root.bar.foreground
      }

      // Filtered to a topic: send there. Otherwise pick a destination.
      Dropdown {
        id: sendPicker
        visible: root.topics.length > 1 && !root.topicFiltered
        width: parent.width
        showLabel: false
        options: root.topics.map(function(t) { return { value: t, label: "Send to " + t } })
        value: root.topics.length > 0 ? root.topics[0] : ""
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
      }

      Row {
        visible: root.ntfy && root.ntfy.configured
        width: parent.width
        spacing: Style.space(6)

        TextField {
          id: sendField
          width: parent.width - sendButton.width - Style.space(6)
          placeholderText: "Message to " + (root.sendTopic || "topic") + "…"
          foreground: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          onAccepted: root.send()
          Keys.onEscapePressed: root.popupOpen = false
        }

        Button {
          id: sendButton
          iconText: "󰒊"
          tooltipText: "Send"
          foreground: root.bar.foreground
          enabled: sendField.text.trim() !== ""
          opacity: enabled ? 1.0 : 0.4
          anchors.verticalCenter: parent.verticalCenter
          onClicked: root.send()
        }
      }
    }
  }
}
