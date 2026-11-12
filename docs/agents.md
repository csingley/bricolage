# The agent-sessions widget

`bricolage.bar.agents` shows the state of coding-agent sessions in the bar's task pill and raises
the window of the one that needs you when it is clicked. It does not track sessions itself. It
reads a **view** from two commands, so it works with any tracker that prints one:

```nix
bricolage.bar.agents = {
  enable = true;
  watchCommand = "${tracker}/bin/tracker watch"; # the view now, and again after each change
  listCommand = "${tracker}/bin/tracker list";   # the view once
};
```

## The view

One JSON object, version 1. A line a time from `watchCommand`, and one object from `listCommand`.

```json
{
  "version": 1,
  "sessions": [
    {"key": {"process": {"pid": 1492557, "startTime": 24683671}},
     "label": "api", "agent": "claude", "state": "waiting",
     "detail": "Bash: make deploy", "ageMs": 1500}
  ]
}
```

| Field | Used for |
|---|---|
| `version` | A view of another version shows the widget as down. |
| `agg.state` | `down` shows the widget as down, for a tracker that cannot reach its daemon. |
| `sessions[].key.process.pid` | The agent's own process, to find the window that holds it. |
| `sessions[].state` | `running`, `idle` or `waiting`. |
| `sessions[].label`, `agent`, `detail` | The tooltip. Whatever they hold is cleaned and escaped. |
| `sessions[].ageMs` | The time the session entered its state, and which of two waits is older. |
| `sessions[].detached` | Marks a background job in the tooltip. |

Unknown fields are ignored.

## What it shows

The widget's class is the most urgent state: `waiting`, then `running`, then `idle`, else `none`,
and `down` when the source cannot be read. The number is the sessions in that state, out of all of
them when others differ.

The command reports the count alone, and the bar formats it as it does the battery and the volume:
the glyph from the bar's icon table, then the count right-aligned in three columns (`{text:>3}`), so
the widget keeps one width and the glyph one place. The count is at most three characters: `1`, `1/2`,
`9+` past nine sessions, `0` with no sessions, `✕` when the source is down. The stylesheet sets no
width for it. Any task source can use the same: `bricolage.bar.tasks.<name>.format` is a waybar
format string in which `{text}` is the text the command reports.

A flashing alert has to be one you can act on. A waiting session that no window holds, such as a
background job with no terminal, counts as idle instead, and its tooltip line says there is no
window to answer it in. A session is held by a window when the process, or one of its parents, owns
a sway window. If sway cannot be asked, or a session's key is not a process, nothing is demoted.

A click raises the window of the most urgent session that has one: waiting, then running, then
idle, and within a state the one that has waited longest.

## Requires

`swaymsg` from the distro, as for the rest of the bar.
