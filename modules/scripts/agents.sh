# shellcheck shell=bash
# agents bar | agents focus: the bar widget for agent sessions, and its click action.
#
# Both read a view of the sessions (version 1: sessions with a key, state, label, age and so on)
# from a command, so they work with any source that prints one.
#   AGENTS_WATCH  a command that prints the view now and after each change, one JSON object a line
#   AGENTS_LIST   a command that prints the view once
#   AGENTS_JQ     the jq program that formats a view for the bar
# And for tests: AGENTS_PROC (default /proc) and AGENTS_SWAYMSG (default /usr/bin/swaymsg).
#
# A session can be answered if a window holds its process: the nearest of the process and its
# parents that owns a window. A terminal's window holds the shell and what the shell runs.
#
# Requires (outside Nix):
#   distro sway - swaymsg
proc=${AGENTS_PROC:-/proc}
swaymsg=${AGENTS_SWAYMSG:-/usr/bin/swaymsg}
max_ancestors=64

# parent PID: the parent of a process, from its stat line; the name in it may hold anything.
parent() {
  local s
  s=$(<"$proc/$1/stat") 2>/dev/null || return 1
  s=${s##*) }
  # shellcheck disable=SC2086 # the fields after the name are numbers and one letter
  set -- $s
  [ -n "${2:-}" ] && echo "$2"
}

# windows: the windows in sway's tree, as {"PID": CONTAINER_ID}. A window is a container with a
# process that holds no others.
windows() {
  "$swaymsg" -t get_tree 2>/dev/null | jq -c '
    [.. | objects | select((.pid? // 0) > 0 and ((.nodes // []) | length) == 0
      and ((.floating_nodes // []) | length) == 0) | {key: (.pid | tostring), value: .id}]
    | from_entries'
}

# window_of PID WINDOWS: the container of the nearest window that holds the process.
window_of() {
  local pid=$1 id i
  for ((i = 0; i < max_ancestors; i++)); do
    id=$(jq -r --arg p "$pid" '.[$p] // empty' <<<"$2")
    if [ -n "$id" ]; then
      echo "$id"
      return 0
    fi
    pid=$(parent "$pid") || return 1
    [ "$pid" -gt 0 ] || return 1
  done
  return 1
}

# The same text as the formatter's, in the same length: the glyph, a no-break space, and three cells.
down='{"class":"down","text":"󰚩 ✕  ","tooltip":"the agent view could not be read"}'

bar() {
  local view waiting pids stranded win pid
  bash -c "$AGENTS_WATCH" | while IFS= read -r view; do
    stranded='[]'
    pids=$(jq -r '.sessions[]? | select(.state == "waiting" and .key.process) | .key.process.pid' <<<"$view" 2>/dev/null) || pids=
    if [ -n "$pids" ] && win=$(windows) && [ -n "$win" ]; then
      waiting=()
      for pid in $pids; do
        window_of "$pid" "$win" >/dev/null || waiting+=("$pid")
      done
      stranded=$(printf '%s\n' "${waiting[@]}" | jq -sc 'map(tonumber)' 2>/dev/null) || stranded='[]'
      [ -n "$stranded" ] || stranded='[]'
    fi
    jq -c --argjson stranded "$stranded" -f "$AGENTS_JQ" <<<"$view" 2>/dev/null || echo "$down"
  done
}

# focus: raise the window of the most urgent session that has one: one that is waiting, then
# running, then idle, and within a state the one that has been in it longest.
focus() {
  local view win pid id
  view=$(bash -c "$AGENTS_LIST") || return 1
  win=$(windows) && [ -n "$win" ] || {
    echo "agents: cannot read sway's windows" >&2
    return 1
  }
  while read -r pid; do
    if id=$(window_of "$pid" "$win"); then
      exec "$swaymsg" "[con_id=$id] focus"
    fi
  done < <(jq -r '
    [.sessions[]? | select(.key.process) | {pid: .key.process.pid, age: (.ageMs // 0),
      r: ({"waiting": 0, "running": 1, "idle": 2}[.state] // 3)}]
    | sort_by([.r, -.age]) | .[].pid' <<<"$view")
  echo "agents: no session has a window" >&2
  return 1
}

case ${1:-} in
bar) bar ;;
focus) focus ;;
*)
  echo "usage: agents bar|focus" >&2
  exit 2
  ;;
esac
