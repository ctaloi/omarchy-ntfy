# omarchy-ntfy

An [ntfy](https://ntfy.sh) plugin for the Omarchy shell. It subscribes to your
topics, shows each message as a desktop notification, and puts a bell in the
bar with an unread count and the most recent messages.

## Install

```bash
omarchy plugin add https://github.com/<you>/omarchy-ntfy.git
omarchy plugin enable ntfy
cp ntfy.example.json ~/.config/omarchy/ntfy.json   # then edit topics
```

## Config (`~/.config/omarchy/ntfy.json`)

```json
{ "server": "https://ntfy.sh", "topics": ["my-topic"], "minPriority": 1 }
```

Changes apply on save. Messages below `minPriority` (1–5) are ignored.

## Usage

- Left-click the bell: show recent messages (marks them read when closed)
- Right-click the bell: mark all read
- Click a message that has a click URL to open it
- Type in the box at the top of the popup and press Enter to send (pick the
  topic from the dropdown when you subscribe to more than one)

From a terminal, script, or Hyprland keybinding:

```bash
omarchy-shell ntfy send my-topic "Backup finished"
omarchy-shell ntfy status
omarchy-shell ntfy markRead
omarchy-shell ntfy clear
```

Messages you send are added to the history as read, without notifying you.

Requires only `curl` and `notify-send`. After sleep or a dropped connection
it reconnects and catches up on missed messages via `?since=`.
