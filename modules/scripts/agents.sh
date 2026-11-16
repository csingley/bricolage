# shellcheck shell=bash
# agents bar | agents focus: the bar widget for agent sessions, and its click action.
#
# Both read a view of the sessions (version 1: sessions with a key, state, label, age and so on)
# from a command, so they work with any source that prints one.
#   AGENTS_WATCH  a command that prints the view now and after each change, one JSON object a line
#   AGENTS_LIST   a command that prints the view once
#   AGENTS_JQ     the jq program that formats a view for the bar
#   AGENTS_ATTACH optional: a command that brings a background job up in a terminal, with {job} in
#                 place of the job's id (the view's sessions[].job)
# And for tests: AGENTS_PROC (default /proc) and AGENTS_SWAYMSG (default /usr/bin/swaymsg).
#
# A session can be answered if a window holds its process: the nearest of the process and its
# parents that owns a window. A terminal's window holds the shell and what the shell runs. A
# background job no terminal is attached to can be answered too, if AGENTS_ATTACH can bring it up.
attach=${AGENTS_ATTACH:-}
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

# The same text as the formatter's for a source that is down; the bar's format adds the glyph.
down='{"class":"down","text":"✕","tooltip":"the agent view could not be read"}'

bar() {
  local view waiting pids stranded win pid
  bash -c "$AGENTS_WATCH" | while IFS= read -r view; do
    stranded='[]'
    pids=$(jq -r --arg attach "$attach" '.sessions[]?
      | select(.state == "waiting" and .key.process and ($attach == "" or (.job // "") == ""))
      | .key.process.pid' <<<"$view" 2>/dev/null) || pids=
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

# attach JOB: bring a background job up with the attach command, in a process of its own, since the
# command may be a terminal that lives as long as the job is shown. The id is agent-written text, so
# only a plain token goes into a command.
attach_job() {
  [[ $1 =~ ^[A-Za-z0-9_-]+$ ]] || return 1
  setsid -f bash -c "${attach//\{job\}/$1}" >/dev/null 2>&1 </dev/null
}

# focus: bring up the most urgent session that can be answered: one that is waiting, then running,
# then idle, and within a state the one that has been in it longest. A session with a window has it
# raised; a background job is attached, when there is a command for it.
focus() {
  local view win kind who id
  view=$(bash -c "$AGENTS_LIST") || return 1
  win=$(windows) && [ -n "$win" ] || {
    echo "agents: cannot read sway's windows" >&2
    return 1
  }
  while IFS=$'\t' read -r kind who; do
    if [ "$kind" = job ]; then
      attach_job "$who" && return 0
    elif id=$(window_of "$who" "$win"); then
      exec "$swaymsg" "[con_id=$id] focus"
    fi
  done < <(jq -r --arg attach "$attach" '
    [.sessions[]? | select(.key.process) | {pid: .key.process.pid, age: (.ageMs // 0),
      job: (if $attach != "" and .detached and (.job // "") != "" then .job else null end),
      r: ({"waiting": 0, "running": 1, "idle": 2}[.state] // 3)}]
    | sort_by([.r, -.age]) | .[] | if .job then "job\t\(.job)" else "pid\t\(.pid)" end' <<<"$view")
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
