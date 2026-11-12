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
[ "$(jq -r .text <<<"$out")" = "󰚩 1/2" ] || fail "text: $out"
jq -e '.tooltip | contains("s2000") and contains("no window to answer it in")' <<<"$out" >/dev/null || fail "tooltip: $out"
[ "$(jq -r .tooltip <<<"$out" | grep -c 'no window')" = 1 ] || fail "only the stranded one is marked: $out"

# Nothing answerable: not a call to act. It is idle, and still counted.
view "$(sess 2000 waiting 9000)" >v2
out=$(bar v2)
[ "$(jq -r .class <<<"$out")" = idle ] || fail "stranded alone: $out"
[ "$(jq -r .text <<<"$out")" = "󰚩 1" ] || fail "stranded text: $out"

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
[ "$(jq -r .class <<<"$out")" = none ] && [ "$(jq -r '.text | length' <<<"$out")" = 1 ] || fail "none: $out"
view "$(sess 1000 running 1),$(sess 3000 idle 1)" >v6
out=$(bar v6)
[ "$(jq -r .class <<<"$out")" = running ] && [ "$(jq -r .text <<<"$out")" = "󰚩 1/2" ] || fail "running: $out"
view "$(sess 1000 idle 1)" >v7
[ "$(bar v7 | jq -r '[.class, .text] | join("|")')" = "idle|󰚩 1" ] || fail "idle"
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

# A process table that loops or runs out ends the search.
proc 40 41
proc 41 40
view "$(sess 40 waiting 1)" >l1
[ "$(timeout 20 bash -c "AGENTS_WATCH='cat l1' bash -o errexit -o nounset -o pipefail '$sh' bar" | jq -r .class)" = idle ] || fail "a loop in the process table"
if bash "$sh" nonsense 2>/dev/null; then fail "a bad mode was accepted"; fi
echo ok
