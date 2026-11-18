#!/usr/bin/env bash
# Tests for modules/scripts/agents.sh and agents.jq, with a fake /proc, a fake swaymsg and
# canned views. Usage: tests/agents.sh AGENTS_SH AGENTS_JQ  (needs bash and jq)
set -euo pipefail
sh=$(realpath "$1")
jq_prog=$(realpath "$2")
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
cd "$t"

fail() { echo "FAIL: $*" >&2; exit 1; }

# A process table: PID PARENT. The name in a stat line may hold spaces and parentheses.
mkdir proc
proc() { mkdir -p "proc/$1"; echo "$1 (a b) c) S $2 0 0" >"proc/$1/stat"; }
proc 500 1      # foot, which owns window 7
proc 900 500    # zsh
proc 1000 900   # claude, in the window
proc 2000 1     # codex with no terminal
proc 600 1      # another window, 9
proc 3000 600   # a job in it
proc 1 0

# sway: a tree with two windows, a floating one among them; focus commands are logged.
cat >tree.json <<'JSON'
{"id":1,"nodes":[{"id":2,"nodes":[{"id":7,"pid":500,"nodes":[]}],"floating_nodes":[{"id":9,"pid":600,"nodes":[]}]}]}
JSON
cat >swaymsg <<'SH'
#!/bin/sh
if [ "$1" = -t ]; then cat tree.json; else echo "$*" >>focus.log; fi
SH
chmod +x swaymsg
export AGENTS_PROC=$t/proc AGENTS_SWAYMSG=$t/swaymsg AGENTS_JQ=$jq_prog

sess() { # PID STATE AGEMS [LABEL]
  printf '{"key":{"process":{"pid":%s,"startTime":1}},"agent":"claude","state":"%s","ageMs":%s,"label":"%s"}' "$1" "$2" "$3" "${4:-s$1}"
}
view() { printf '{"version":1,"host":"h","agg":{"state":"x"},"sessions":[%s]}\n' "$*"; }
bar() { AGENTS_WATCH="cat $1" bash -o errexit -o nounset -o pipefail "$sh" bar; }

# One answerable waiting session and one with no window: the bar asks for one.
view "$(sess 1000 waiting 5000),$(sess 2000 waiting 9000)" >v1
out=$(bar v1)
[ "$(jq -r .class <<<"$out")" = waiting ] || fail "class: $out"
[ "$(jq -r .text <<<"$out")" = "1/2" ] || fail "text: $out"
jq -e '.tooltip | contains("s2000") and contains("no window to answer it in")' <<<"$out" >/dev/null || fail "tooltip: $out"
[ "$(jq -r .tooltip <<<"$out" | grep -c 'no window')" = 1 ] || fail "only the stranded one is marked: $out"

# Nothing answerable: not a call to act. It is idle, and still counted.
view "$(sess 2000 waiting 9000)" >v2
out=$(bar v2)
[ "$(jq -r .class <<<"$out")" = idle ] || fail "stranded alone: $out"
[ "$(jq -r .text <<<"$out")" = "1" ] || fail "stranded text: $out"

# A session held by a window further up the process tree is answerable.
view "$(sess 3000 waiting 1)" >v3
[ "$(bar v3 | jq -r .class)" = waiting ] || fail "a floating window's child"

# With no way to ask sway, nothing is judged and the alert stands.
out=$(AGENTS_SWAYMSG=/bin/false bar v2)
[ "$(jq -r .class <<<"$out")" = waiting ] || fail "no sway: $out"

# A session that is not a process cannot be found among windows and is left as it was.
view '{"key":{"tmux":{"socket":"s","serverPid":1,"pane":"%1"}},"agent":"x","state":"waiting","ageMs":1}' >v4
[ "$(bar v4 | jq -r .class)" = waiting ] || fail "a tmux session"

# The other classes, a view of a later version, a source that is down, and a line that is no view.
view >v5
out=$(bar v5)
[ "$(jq -r .class <<<"$out")" = none ] && [ "$(jq -r .text <<<"$out")" = "0" ] || fail "none: $out"
view "$(sess 1000 running 1),$(sess 3000 idle 1)" >v6
out=$(bar v6)
[ "$(jq -r .class <<<"$out")" = running ] && [ "$(jq -r .text <<<"$out")" = "1/2" ] || fail "running: $out"
view "$(sess 1000 idle 1)" >v7
[ "$(bar v7 | jq -r '[.class, .text] | join("|")')" = "idle|1" ] || fail "idle"
echo '{"version":2,"host":"h","agg":{"state":"idle"},"sessions":[]}' >v8
[ "$(bar v8 | jq -r .class)" = down ] || fail "a later version"
echo '{"version":1,"host":"","agg":{"state":"down"},"sessions":[]}' >v9
[ "$(bar v9 | jq -r .class)" = down ] || fail "down"
echo 'not json' >v10
out=$(bar v10)
[ "$(jq -r .class <<<"$out")" = down ] || fail "garbage: $out"

# What an agent wrote cannot reach the bar as markup or control characters, and long text is clipped.
long=$(head -c 500 /dev/zero | tr '\0' z)
evil='{"key":{"opaque":"o"},"label":"<u>lbl</u>","agent":"<b>x</b>","state":"waiting","detail":"a<i>&\u001b[31m\nb‮c​d e󠀁f","ageMs":90000}'
view "$evil,{\"key\":{\"opaque\":\"p\"},\"agent\":\"c\",\"state\":\"waiting\",\"detail\":\"$long\",\"ageMs\":1}" >v11
out=$(bar v11)
if grep -q '<b>\|<i>\|<u>' <<<"$out"; then fail "markup got through: $out"; fi
grep -q '&lt;u&gt;lbl&lt;/u&gt;' <<<"$out" || fail "markup was not escaped: $out"
jq -e '.tooltip | test("[\u001b\u202e\u200b\u2028\udb40\udc01]") | not' <<<"$out" >/dev/null || fail "control or format characters got through: $out"
[ "$(jq -r .tooltip <<<"$out" | wc -c)" -lt 600 ] || fail "long text was not clipped"

# A background job is named as one.
view '{"key":{"process":{"pid":1000,"startTime":1}},"label":"work","state":"idle","ageMs":1,"detached":true}' >v12
jq -e '.tooltip | contains("work (background job)")' <<<"$(bar v12)" >/dev/null || fail "a detached job"

# The number is the sessions in the leading state, out of all of them when others differ: "1/2" is
# one of two, and a bare number means every session is alike.
s() { printf '{"key":{"opaque":"%s"},"agent":"c","state":"%s","ageMs":1}' "$1" "$2"; }
{
  view "$(s a waiting),$(s b running)"
  view "$(s a waiting),$(s b waiting)"
  view "$(s a running),$(s b running),$(s c idle)"
  view "$(s a idle),$(s b idle)"
} >counts
[ "$(bar counts | jq -r .text | tr '\n' ' ')" = "1/2 2 2/3 2 " ] || fail "counts: $(bar counts | jq -r .text | tr '\n' '|')"

# The text is the count alone, never empty, and fits the three characters the bar's format gives it
# (`{text:>3}`, as the other widgets give their numbers), so the widget keeps one width: the glyph and
# the alignment are the bar's, not the formatter's. Past nine sessions the count reads "9+".
many=$(for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf '%s,' "$(s "k$i" idle)"; done)
view "${many%,}" >many
echo '{"version":1,"host":"","agg":{"state":"down"},"sessions":[]}' >down
for f in v1 v2 v3 v5 v6 v7 v8 v9 v10 many down counts; do
  bar "$f" | jq -e '.text | length >= 1 and length <= 3' >/dev/null || fail "the text does not fit its field in $f: $(bar "$f" | jq -r .text | tr '\n' '|')"
done
for f in v1 v2 v3 v5 v6 v7 v8 v9 v10 many down counts; do
  if bar "$f" | jq -r .text | grep -q "󰚩\|[[:space:]]"; then fail "the text carries a glyph or padding in $f, which the bar's format supplies"; fi
done
[ "$(bar many | jq -r .text)" = "9+" ] || fail "many: $(bar many | jq -r .text)"
[ "$(bar v8 | jq -r .text)" = "✕" ] && [ "$(bar v10 | jq -r .text)" = "✕" ] || fail "a source that is down shows the cross"

# A session's time in its state is the moment it began, which does not go stale on a bar that shows
# a line until the next change.
out=$(bar v1)
grep -Eq 'waiting since ([0-9]{2}:[0-9]{2}|[A-Z][a-z]{2} [0-9]{2}:[0-9]{2})' <<<"$out" || fail "since: $out"
if grep -Eq 'waiting [0-9]+[smhd]' <<<"$out"; then fail "a duration was shown: $out"; fi

# focus: the most urgent session that has a window; one with none is passed over.
focus() { AGENTS_LIST="cat $1" bash -o errexit -o nounset -o pipefail "$sh" focus; }
: >focus.log
view "$(sess 2000 waiting 9000),$(sess 3000 idle 5),$(sess 1000 running 1)" >f1
focus f1
[ "$(cat focus.log)" = "[con_id=7] focus" ] || fail "focus went to: $(cat focus.log)"
: >focus.log
view "$(sess 1000 waiting 10),$(sess 3000 waiting 99)" >f2
focus f2
[ "$(cat focus.log)" = "[con_id=9] focus" ] || fail "the longer wait should come first: $(cat focus.log)"
: >focus.log
view "$(sess 2000 waiting 9000)" >f3
if focus f3 2>err; then fail "focus with no window succeeded"; fi
grep -q 'no session has a window' err || fail "focus said: $(cat err)"
[ ! -s focus.log ] || fail "focus acted with no window"
if AGENTS_SWAYMSG=/bin/false focus f1 2>err; then fail "focus without sway succeeded"; fi

# A background job no window holds is brought up by the attach command, with its job id in place of
# {job}, when one is set. It is a candidate in the same order as a session with a window.
job() { # PID STATE AGEMS JOB
  printf '{"key":{"process":{"pid":%s,"startTime":1}},"agent":"claude","state":"%s","ageMs":%s,"detached":true,"job":"%s"}' "$1" "$2" "$3" "$4"
}
attach() { # VIEW: run focus with an attach command that logs its argument, and wait for the log
  : >attach.log
  local status=0
  AGENTS_ATTACH='echo {job} >>attach.log' focus "$1" || status=$?
  for _ in $(seq 50); do [ -s attach.log ] && break; sleep 0.1; done
  return "$status"
}
: >focus.log
view "$(job 2000 waiting 5 35ccf30d),$(sess 1000 idle 1)" >j1
attach j1
[ "$(cat attach.log)" = 35ccf30d ] || fail "a waiting job should be attached before an idle window: $(cat attach.log)"
[ ! -s focus.log ] || fail "a window was raised as well: $(cat focus.log)"
view "$(job 2000 running 5 35ccf30d),$(sess 1000 waiting 1)" >j2
attach j2
[ ! -s attach.log ] && [ "$(cat focus.log)" = "[con_id=7] focus" ] || fail "a waiting window comes before a running job"
: >focus.log
view "$(job 2000 waiting 5 35ccf30d)" >j4
if focus j4 2>err; then fail "a job was attached with no attach command"; fi
[ ! -s focus.log ] || fail "no attach command, and a window was raised for a job"
# A job id that is not a plain token is never put in a command.
view "$(job 2000 waiting 5 'x; touch pwned')" >j3
if attach j3 2>err; then fail "an unsafe job id was accepted"; fi
[ ! -e pwned ] && [ ! -s attach.log ] || fail "an unsafe job id reached the command"
# With an attach command a waiting job is a call to act; without one it still counts as idle.
[ "$(AGENTS_ATTACH=true bar j1 | jq -r .class)" = waiting ] || fail "a job that can be attached is answerable"
[ "$(bar j1 | jq -r .class)" = idle ] || fail "a job with no way to attach is not"

# pick: every session in a menu, in focus's order; the chosen line's number says which. The fake menu
# keeps what it was shown and answers with $ANSWER (a line, or nothing for Escape).
cat >menu <<'SH'
#!/bin/sh
[ "$*" = "--app-id agents-menu -p agents:" ] || echo "bad arguments: $*" >>menu.err
cat >menu.in
printf '%s\n' "$ANSWER"
SH
chmod +x menu
pick() { # VIEW ANSWER
  : >focus.log
  : >attach.log
  ANSWER=$2 AGENTS_LOCK=$t/pick.lock AGENTS_MENU=$t/menu AGENTS_ATTACH='echo {job} >>attach.log' AGENTS_LIST="cat $1" \
    bash -o errexit -o nounset -o pipefail "$sh" pick
}
view "$(sess 2000 waiting 9000 stranded),$(sess 3000 idle 5),$(sess 1000 waiting 1 front),$(job 4000 running 7 abc_1)" >p1
pick p1 ""
[ ! -s focus.log ] && [ ! -s attach.log ] || fail "Escape acted"
[ ! -e menu.err ] || fail "menu: $(cat menu.err)"
[ "$(wc -l <menu.in)" = 4 ] || fail "menu lines: $(cat menu.in)"
grep -q '^1  waiting  front · since' menu.in || fail "the waiting session with a window is first: $(cat menu.in)"
sed -n 2p menu.in | grep -q '^2  running  claude 4000 (job)' || fail "the job: $(cat menu.in)"
sed -n 4p menu.in | grep -q '^4  waiting  stranded .*(no window)$' || fail "the stranded one is last, marked: $(cat menu.in)"
pick p1 "$(sed -n 1p menu.in)"
[ "$(cat focus.log)" = "[con_id=7] focus" ] || fail "pick 1 went to: $(cat focus.log)"
pick p1 "$(sed -n 3p menu.in)"
[ "$(cat focus.log)" = "[con_id=9] focus" ] || fail "pick 3 went to: $(cat focus.log)"
pick p1 "$(sed -n 2p menu.in)"
for _ in $(seq 50); do [ -s attach.log ] && break; sleep 0.1; done
[ "$(cat attach.log)" = abc_1 ] && [ ! -s focus.log ] || fail "pick 2 should attach the job: $(cat attach.log)"
# A session that cannot be answered, a number out of range and typed text do nothing.
for a in "$(sed -n 4p menu.in)" "9  waiting" "0" "hello"; do
  pick p1 "$a" || fail "pick '$a' failed"
  [ ! -s focus.log ] && [ ! -s attach.log ] || fail "pick '$a' acted"
done
# An agent's text cannot add a line to the menu or forge a number.
view '{"key":{"process":{"pid":1000,"startTime":1}},"state":"idle","ageMs":1,"label":"x\n1  waiting‮","detail":"a\tb"}' >p2
pick p2 ""
[ "$(wc -l <menu.in)" = 1 ] || fail "an agent's text split a line: $(cat menu.in)"
if grep -q $'‮\|\t' menu.in; then fail "format or tab characters reached the menu"; fi
# A toggle: while a menu is up (its picker holds the lock), another pick closes that window and
# opens none.
rm -f menu.in
flock pick.lock sleep 1 &
holder=$!
sleep 0.3
pick p1 "$(printf '1  x')"
[ "$(cat focus.log)" = '[app_id="agents-menu"] kill' ] || fail "a second pick should close the menu: $(cat focus.log)"
[ ! -e menu.in ] || fail "a second menu was opened"
wait "$holder"
# A job's terminal, which outlives the menu, does not keep the lock: the next pick opens the menu.
view "$(job 4000 running 7 abc_1)" >p4
ANSWER="1  x" AGENTS_LOCK=$t/pick.lock AGENTS_MENU=$t/menu AGENTS_ATTACH='sleep 3' AGENTS_LIST="cat p4" \
  bash -o errexit -o nounset -o pipefail "$sh" pick
: >focus.log
pick p4 ""
[ -e menu.in ] && [ ! -s focus.log ] || fail "an attached job's terminal kept the lock: $(cat focus.log)"

# No sessions: the menu says so, and nothing is done.
view >p3
pick p3 "no agent sessions"
grep -qx 'no agent sessions' menu.in && [ ! -s focus.log ] || fail "no sessions: $(cat menu.in)"

# A session an application hosts is brought up by the command for its entrypoint, with its id in place of {session}, and not by a window:
# the application's one window holds every session it hosts. Both words go into a command, so only plain tokens do.
hosted() { # PID STATE AGEMS ENTRYPOINT SESSION
  printf '{"key":{"process":{"pid":%s,"startTime":1}},"agent":"claude","state":"%s","ageMs":%s,"entrypoint":"%s","hostSession":"%s"}' "$1" "$2" "$3" "$4" "$5"
}
OPEN='{"claude-desktop":"echo {session} >>open.log"}'
opened() { # VIEW: run focus with an open command that logs its argument, and wait for the log
  : >open.log
  local status=0
  AGENTS_OPEN=$OPEN focus "$1" || status=$?
  for _ in $(seq 50); do [ -s open.log ] && break; sleep 0.1; done
  return "$status"
}
: >focus.log
view "$(hosted 2000 waiting 5 claude-desktop local_05ed-31),$(sess 1000 idle 1)" >h1
opened h1
[ "$(cat open.log)" = local_05ed-31 ] || fail "a waiting hosted session should be opened before an idle window: $(cat open.log)"
[ ! -s focus.log ] || fail "a window was raised as well: $(cat focus.log)"
# A hosted session whose process has a window is still opened by its command: the window is the application's.
view "$(hosted 1000 idle 5 claude-desktop local_9)" >h2
opened h2
[ "$(cat open.log)" = local_9 ] && [ ! -s focus.log ] || fail "a hosted session in a window: $(cat open.log) $(cat focus.log)"
# An entrypoint with no command, an unsafe id, and no commands at all leave it to the window, or to nothing.
view "$(hosted 2000 waiting 5 cli local_1)" >h3
if opened h3 2>err; then fail "an entrypoint with no command was opened"; fi
[ ! -s open.log ] || fail "opened with no command for the entrypoint: $(cat open.log)"
view "$(hosted 2000 waiting 5 claude-desktop 'x; touch pwned')" >h4
if opened h4 2>err; then fail "an unsafe session id was accepted"; fi
[ ! -e pwned ] && [ ! -s open.log ] || fail "an unsafe session id reached the command"
: >open.log
view "$(hosted 2000 waiting 5 claude-desktop local_1)" >h6
if focus h6 2>err; then fail "a hosted session was opened with no open commands"; fi
[ ! -s open.log ] || fail "opened with no open commands"
# It counts as answerable in the bar without a window, and not when nothing can open it.
[ "$(AGENTS_OPEN=$OPEN bar h1 | jq -r .class)" = waiting ] || fail "a hosted session that can be opened is answerable"
[ "$(bar h6 | jq -r .class)" = idle ] || fail "a hosted session nothing can open is not"
# The menu lists it, and choosing it runs its command.
: >open.log
view "$(hosted 2000 waiting 5 claude-desktop local_7 )" >h5
ANSWER="1  x" AGENTS_LOCK=$t/pick.lock AGENTS_MENU=$t/menu AGENTS_OPEN=$OPEN AGENTS_LIST="cat h5" \
  bash -o errexit -o nounset -o pipefail "$sh" pick
for _ in $(seq 50); do [ -s open.log ] && break; sleep 0.1; done
[ "$(cat open.log)" = local_7 ] || fail "choosing a hosted session: $(cat open.log)"
! grep -q 'no window' menu.in || fail "a hosted session was listed as having no window: $(cat menu.in)"

# A process table that loops or runs out ends the search.
proc 40 41
proc 41 40
view "$(sess 40 waiting 1)" >l1
[ "$(timeout 20 bash -c "AGENTS_WATCH='cat l1' bash -o errexit -o nounset -o pipefail '$sh' bar" | jq -r .class)" = idle ] || fail "a loop in the process table"
if bash "$sh" nonsense 2>/dev/null; then fail "a bad mode was accepted"; fi
echo ok
