import QtQuick
import Quickshell
import Quickshell.Io

// Headless ntfy subscriber. One long-lived `curl` stream per shell session
// (not per bar/monitor), turning each message into a desktop notification
// and keeping a short history for the bar widget.
//
// Config:  ~/.config/omarchy/ntfy.json   { server, topics[], minPriority }
// State:   ~/.local/state/omarchy/ntfy/state.json  { lastId, messages[] }
Item {
  id: root

  property var shell: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/omarchy/ntfy.json"
  readonly property string stateDir: home + "/.local/state/omarchy/ntfy"
  readonly property int maxMessages: 50
  readonly property int stallTimeoutMs: 120000

  property string server: "https://ntfy.sh"
  property var topics: []
  property int minPriority: 1
  property bool configured: topics.length > 0

  property var messages: []
  property int unreadCount: 0
  property string lastId: ""
  property bool connected: false
  property string status: "Not configured"
  property int backoffMs: 1000
  property bool stateLoaded: false
  property var seen: ({})
  property var pendingSent: ({})

  readonly property var tagEmoji: ({
    "warning": "⚠️", "rotating_light": "🚨", "white_check_mark": "✅",
    "heavy_check_mark": "✔️", "x": "❌", "skull": "💀", "tada": "🎉",
    "+1": "👍", "-1": "👎", "partying_face": "🥳", "loudspeaker": "📢",
    "bell": "🔔", "computer": "💻", "fire": "🔥", "no_entry": "⛔",
    "package": "📦", "lock": "🔒", "key": "🔑", "zap": "⚡", "bug": "🐛"
  })

  function streamUrl() {
    var base = String(server || "https://ntfy.sh").replace(/\/+$/, "")
    var url = base + "/" + topics.map(encodeURIComponent).join(",") + "/json"
    return lastId ? url + "?since=" + encodeURIComponent(lastId) : url
  }

  function applyConfig(text) {
    var cfg = {}
    try { cfg = JSON.parse(text || "{}") } catch (e) {
      status = "Invalid ntfy.json: " + e
      cfg = {}
    }
    var nextTopics = Array.isArray(cfg.topics) ? cfg.topics.map(String).filter(function(t) { return t !== "" })
      : (cfg.topic ? [String(cfg.topic)] : [])
    server = cfg.server ? String(cfg.server) : "https://ntfy.sh"
    minPriority = Number(cfg.minPriority) || 1
    topics = nextTopics
    reconnect(true)
  }

  function reconnect(immediate) {
    stream.running = false
    connected = false
    retryTimer.stop()
    if (!configured) {
      status = "Not configured"
      return
    }
    if (!stateLoaded) return
    if (immediate) {
      backoffMs = 1000
      startStream()
    } else {
      status = "Reconnecting in " + Math.round(backoffMs / 1000) + "s"
      retryTimer.interval = backoffMs
      retryTimer.start()
      backoffMs = Math.min(backoffMs * 2, 60000)
    }
  }

  function startStream() {
    stream.command = ["curl", "-sSN", "--fail", "--connect-timeout", "15", streamUrl()]
    stream.running = true
    status = "Connecting…"
    watchdog.restart()
  }

  function handleLine(line) {
    watchdog.restart()
    var evt
    try { evt = JSON.parse(line) } catch (e) { return }
    if (!evt || !evt.event) return

    if (evt.event === "open") {
      connected = true
      backoffMs = 1000
      status = "Connected to " + topics.join(", ")
      return
    }
    if (evt.event !== "message" || seen[evt.id]) return
    if (pendingSent[evt.topic + "\n" + evt.message]) {
      lastId = evt.id
      recordSent(evt)
      return
    }

    seen[evt.id] = true
    lastId = evt.id
    var priority = Number(evt.priority) || 3
    var msg = {
      id: evt.id,
      time: Number(evt.time) || Math.floor(Date.now() / 1000),
      topic: evt.topic || "",
      title: evt.title || "",
      message: evt.message || "",
      priority: priority,
      tags: (evt.tags || []).filter(function(t) { return !root.tagEmoji[t] }),
      emoji: (evt.tags || []).map(function(t) { return root.tagEmoji[t] || "" }).join(""),
      click: evt.click || "",
      read: false
    }

    if (priority < minPriority) return

    var next = [msg].concat(messages)
    if (next.length > maxMessages) next = next.slice(0, maxMessages)
    messages = next
    unreadCount = unreadCount + 1
    notify(msg)
    saveState()
  }

  function notify(msg) {
    var urgency = msg.priority >= 5 ? "critical" : (msg.priority <= 2 ? "low" : "normal")
    var title = (msg.emoji ? msg.emoji + " " : "") + (msg.title || msg.topic)
    Quickshell.execDetached(["notify-send", "-a", "ntfy", "-u", urgency, title, msg.message])
  }

  function markAllRead() {
    if (unreadCount === 0) return
    messages = messages.map(function(m) { var c = Object.assign({}, m); c.read = true; return c })
    unreadCount = 0
    saveState()
  }

  function clearMessages() {
    messages = []
    unreadCount = 0
    saveState()
  }

  // ntfy echoes our own publish back on the stream. Record it from the
  // publish response (marked read, no popup) so the echo is a no-op.
  function publish(topic, text) {
    if (!topic || !text || publisher.running) return
    var base = String(server || "https://ntfy.sh").replace(/\/+$/, "")
    publisher.command = ["curl", "-sS", "--fail", "-d", text, base + "/" + encodeURIComponent(topic)]
    pendingSent[topic + "\n" + text] = true
    publisher.running = true
  }

  function recordSent(line) {
    var evt
    try { evt = typeof line === "string" ? JSON.parse(line) : line } catch (e) { return }
    if (!evt || !evt.id || seen[evt.id]) return
    delete pendingSent[evt.topic + "\n" + evt.message]
    seen[evt.id] = true
    var msg = {
      id: evt.id, time: Number(evt.time) || Math.floor(Date.now() / 1000),
      topic: evt.topic || "", title: "", message: evt.message || "",
      priority: 3, tags: [], emoji: "", click: "", read: true, sent: true
    }
    messages = [msg].concat(messages).slice(0, maxMessages)
    saveState()
  }

  function openMessage(msg) {
    if (msg && msg.click) Quickshell.execDetached(["xdg-open", msg.click])
  }

  function saveState() {
    stateFile.setText(JSON.stringify({ lastId: lastId, messages: messages }) + "\n")
  }

  function loadState(text) {
    try {
      var s = JSON.parse(text || "{}")
      lastId = s.lastId || ""
      messages = Array.isArray(s.messages) ? s.messages : []
      var ids = {}
      var unread = 0
      for (var i = 0; i < messages.length; i++) {
        ids[messages[i].id] = true
        if (!messages[i].read) unread++
      }
      seen = ids
      unreadCount = unread
    } catch (e) {}
    stateLoaded = true
    reconnect(true)
  }

  Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", stateDir])

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyConfig(text())
    onLoadFailed: root.applyConfig("{}")
  }

  FileView {
    id: stateFile
    path: root.stateDir + "/state.json"
    printErrors: false
    onLoaded: if (!root.stateLoaded) root.loadState(text())
    onLoadFailed: if (!root.stateLoaded) root.loadState("{}")
  }

  Process {
    id: stream
    stdout: SplitParser {
      onRead: function(line) { root.handleLine(line) }
    }
    stderr: SplitParser {
      onRead: function(line) { root.status = String(line).trim() }
    }
    onExited: function(code) {
      root.connected = false
      // Ignore exits from a stream we deliberately replaced.
      if (root.configured && !stream.running && !retryTimer.running) root.reconnect(false)
    }
  }

  // omarchy-shell ntfy send <topic> <message> | markRead | clear | status
  IpcHandler {
    target: "ntfy"

    function send(topic: string, message: string): void { root.publish(topic, message) }
    function markRead(): void { root.markAllRead() }
    function clear(): void { root.clearMessages() }
    function status(): string { return root.status + " (" + root.unreadCount + " unread)" }
  }

  Process {
    id: publisher
    stdout: SplitParser {
      onRead: function(line) { root.recordSent(line) }
    }
    stderr: SplitParser {
      onRead: function(line) {
        Quickshell.execDetached(["notify-send", "-a", "ntfy", "-u", "normal", "ntfy send failed", String(line).trim()])
      }
    }
  }

  // ntfy sends a keepalive roughly every 45s; silence beyond that means the
  // socket died without curl noticing (common after suspend/resume).
  Timer {
    id: watchdog
    interval: root.stallTimeoutMs
    repeat: false
    onTriggered: if (stream.running) stream.running = false
  }

  Timer {
    id: retryTimer
    repeat: false
    onTriggered: root.startStream()
  }
}
