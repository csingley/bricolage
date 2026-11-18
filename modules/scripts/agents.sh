# shellcheck shell=bash
# agents bar | agents pick | agents focus: the bar widget for agent sessions, and its actions.
#   bar    the widget's text, now and after each change
#   pick   a menu of the sessions, most urgent first; the one chosen is raised (or its job attached)
#   focus  raise the most urgent session that can be answered, with no menu
#
# Both read a view of the sessions (version 1: sessions with a key, state, label, age and so on)
# from a command, so they work with any source that prints one.
#   AGENTS_WATCH  a command that prints the view now and after each change, one JSON object a line
#   AGENTS_LIST   a command that prints the view once
#   AGENTS_JQ     the jq program that formats a view for the bar
#   AGENTS_ATTACH optional: a command that brings a background job up in a terminal, with {job} in
#                 place of the job's id (the view's sessions[].job)
#   AGENTS_OPEN   optional: a JSON object of commands, by what started the agent (the view's
#                 sessions[].entrypoint, such as "claude-desktop"), that bring one of its sessions up in
#                 the application that hosts it, with {session} in place of the session's id
#                 (sessions[].hostSession). Such a session is answered by its command and not by a window,
#                 since the application's one window holds them all.
# And for tests: AGENTS_PROC (default /proc), AGENTS_SWAYMSG (default /usr/bin/swaymsg) and
# AGENTS_MENU (default menu: Bricolage's dmenu-style menu, choices on stdin, the chosen line out).
#
# A session can be answered if a window holds its process: the nearest of the process and its
# parents that owns a window. A terminal's window holds the shell and what the shell runs. A
# background job no terminal is attached to can be answered too, if AGENTS_ATTACH can bring it up.
attach=${AGENTS_ATTACH:-}
open=${AGENTS_OPEN:-}
[ -n "$open" ] || open='{}'
# A session the open commands can bring up: its entrypoint has one, and both words that go into it are plain tokens. The ids come from the
# agent, so nothing else is put in a command.
# shellcheck disable=SC2016 # a jq program, which jq expands, not the shell
openable='def openable($open): ((.entrypoint // "") | test("^[A-Za-z0-9_-]+$")) and ((.hostSession // "") | test("^[A-Za-z0-9_-]+$")) and (($open[.entrypoint] // "") != "");'
#
# Requires (outside Nix):
#   distro sway - swaymsg
proc=${AGENTS_PROC:-/proc}
swaymsg=${AGENTS_SWAYMSG:-/usr/bin/swaymsg}
menu=${AGENTS_MENU:-menu}
# The agents menu's window, and the lock its picker holds while the menu is up.
menu_app=agents-menu
lock=${AGENTS_LOCK:-${XDG_RUNTIME_DIR:-/tmp}/bricolage-agents-pick.lock}
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
    pids=$(jq -r --arg attach "$attach" --argjson open "$open" "$openable"'.sessions[]?
      | select(.state == "waiting" and .key.process and ($attach == "" or (.job // "") == "") and (openable($open) | not))
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
  # Not with the picker's lock (fd 9): a terminal that outlived the menu would hold it.
  setsid -f bash -c "${attach//\{job\}/$1}" >/dev/null 2>&1 </dev/null 9>&-
}

# open_session ENTRYPOINT/SESSION: bring a hosted session up with the command for its entrypoint, in a process of its own. Both words were
# checked by openable.
open_session() {
  local entry=${1%%/*} id=${1#*/} cmd
  cmd=$(jq -r --arg e "$entry" '.[$e] // empty' <<<"$open") && [ -n "$cmd" ] || return 1
  setsid -f bash -c "${cmd//\{session\}/$id}" >/dev/null 2>&1 </dev/null 9>&-
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
    elif [ "$kind" = open ]; then
      open_session "$who" && return 0
    elif id=$(window_of "$who" "$win"); then
      exec "$swaymsg" "[con_id=$id] focus"
    fi
  done < <(jq -r --arg attach "$attach" --argjson open "$open" "$openable"'
    [.sessions[]? | select(.key.process) | {pid: .key.process.pid, age: (.ageMs // 0),
      job: (if $attach != "" and .detached and (.job // "") != "" then .job else null end),
      open: (if openable($open) then "\(.entrypoint)/\(.hostSession)" else null end),
      r: ({"waiting": 0, "running": 1, "idle": 2}[.state] // 3)}]
    | sort_by([.r, -.age]) | .[]
    | if .job then "job\t\(.job)" elif .open then "open\t\(.open)" else "pid\t\(.pid)" end' <<<"$view")
  echo "agents: no session has a window" >&2
  return 1
}

# pick: a menu of every session, in focus's order with those that cannot be answered last, one line each: a number, the state, the name and
# since when, and what it is doing. The number is how the chosen line is found again, since the rest
# is agent-written text; that text is cleaned of control and format characters and clipped. A session
# that cannot be answered is listed, marked, and choosing it does nothing.
#
# It is a toggle, with one menu at most: the picker holds a lock while its menu is up, and a second
# one that finds the lock taken closes that menu's window instead of opening another.
pick() {
  local view win kind who text n i choice id
  local -a kinds=() whos=() lines=() rest=()
  exec 9>"$lock"
  if ! flock -n 9; then
    "$swaymsg" "[app_id=\"$menu_app\"] kill" >/dev/null 2>&1 || true
    return 0
  fi
  view=$(bash -c "$AGENTS_LIST") || return 1
  win=$(windows) || win=
  while IFS=$'\t' read -r kind who text; do
    if [ "$kind" = none ] || { [ "$kind" = pid ] && ! { [ -n "$win" ] && window_of "$who" "$win" >/dev/null; }; }; then
      rest+=("$text  (no window)")
      continue
    fi
    kinds+=("$kind")
    whos+=("$who")
    lines+=("$text")
  done < <(jq -r --arg attach "$attach" --argjson open "$open" "$openable"'
    def clean: gsub("[[:cntrl:]\\p{Zl}\\p{Zp}]"; " ") | gsub("\\p{Cf}"; "");
    def safe(n): tostring | clean | if length > n then .[0:n] + "…" else . end;
    def since:
      (now - (. / 1000)) as $t
      | if ($t | strflocaltime("%F")) == (now | strflocaltime("%F"))
        then $t | strflocaltime("%H:%M") else $t | strflocaltime("%a %H:%M") end;
    [.sessions[]? | {
      pid: .key.process.pid,
      job: (if $attach != "" and .detached and ((.job // "") | test("^[A-Za-z0-9_-]+$")) then .job else null end),
      open: (if openable($open) then "\(.entrypoint)/\(.hostSession)" else null end),
      r: ({"waiting": 0, "running": 1, "idle": 2}[.state] // 3), age: (.ageMs // 0),
      text: ("\(.state // "?" | safe(10) | . + "        " | .[0:8]) "
        + (if (.label // "") != "" then .label | safe(40)
           else "\(.agent // "agent" | safe(20)) \(.key.process.pid // "")" end)
        + (if .detached then " (job)" else "" end)
        + " · since \(.ageMs // 0 | since)"
        + (if (.detail // "") != "" then " · " + (.detail | safe(60)) else "" end))
    }] | sort_by([.r, -.age]) | .[]
    | [if .job then "job", .job elif .open then "open", .open elif .pid then "pid", (.pid | tostring) else "none", "-" end, .text]
    | join("\t")' <<<"$view")
  for text in "${rest[@]}"; do
    kinds+=(none)
    whos+=(-)
    lines+=("$text")
  done
  if [ ${#lines[@]} -eq 0 ]; then
    echo "no agent sessions" | "$menu" --app-id "$menu_app" -p "agents:" >/dev/null
    return 0
  fi
  choice=$(for i in "${!lines[@]}"; do printf '%d  %s\n' $((i + 1)) "${lines[i]}"; done |
    "$menu" --app-id "$menu_app" -p "agents:") || return 0
  n=${choice%% *}
  [[ $n =~ ^[0-9]+$ ]] && ((n >= 1 && n <= ${#lines[@]})) || return 0
  i=$((n - 1))
  case ${kinds[i]} in
  job) attach_job "${whos[i]}" ;;
  open) open_session "${whos[i]}" ;;
  pid) id=$(window_of "${whos[i]}" "$win") && exec "$swaymsg" "[con_id=$id] focus" ;;
  esac
  return 0
}

case ${1:-} in
bar) bar ;;
pick) pick ;;
focus) focus ;;
*)
  echo "usage: agents bar|pick|focus" >&2
  exit 2
  ;;
esac
