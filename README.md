# omarchy-ntfy

An [ntfy](https://ntfy.sh) plugin for the Omarchy shell. It subscribes to your
topics, shows each message as a desktop notification, and puts a bell in the
bar with an unread count and the most recent messages.

## Install

```bash
omarchy plugin add https://github.com/ctaloi/omarchy-ntfy.git
omarchy plugin enable ntfy
cp ntfy.example.json ~/.config/omarchy/ntfy.json   # then edit topics
```

## Config (`~/.config/omarchy/ntfy.json`)

```json
{
  "server": "https://ntfy.sh",
  "topics": ["alerts", "ci", "homelab"],
  "minPriority": 1,
  "muted": ["ci"]
}
```

Changes apply on save. Messages below `minPriority` (1–5) are ignored.
Topics in `muted` are still collected in the panel but never pop up a
notification.

## Usage

- Hover the bell: unread count and the busiest topics
- Left-click the bell: open the panel; right-click: mark everything read
- Filter the panel to All, Unread, or one topic (unread counts are shown in
  the dropdown). Click a topic name under a message to jump to that topic.
- Closing the panel marks what it showed as read: just that topic when
  filtered to one, otherwise everything
- Click a message that has a click URL to open it
- Type in the box at the bottom and press Enter to send. When filtered to a
  topic it sends there; otherwise pick the destination from the dropdown.

From a terminal, script, or Hyprland keybinding:

```bash
omarchy-shell ntfy send my-topic "Backup finished"
omarchy-shell ntfy toggle            # open/close the panel on the focused monitor
omarchy-shell ntfy filter alerts     # or __unread / __all
omarchy-shell ntfy status
omarchy-shell ntfy markRead
omarchy-shell ntfy clear
```

For example, in `~/.config/hypr/bindings.lua` you could bind a key to
`omarchy-shell ntfy toggle`.

Messages you send are added to the history as read, without notifying you.

Requires only `curl` and `notify-send`. After sleep or a dropped connection
it reconnects and catches up on missed messages via `?since=`.
