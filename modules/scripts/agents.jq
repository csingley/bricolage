# Turns one agent view (version 1: a list of sessions, each with a state) into waybar's
# custom-module JSON, {text, class, tooltip}. The class is one of none, idle, running, waiting or
# down, for the bar's CSS. The text is never empty, so the widget always has something to show.
#
# $stranded is the pids of the waiting sessions that no window holds. A call to act has to be one
# that can be acted on, so such a session counts as idle and its tooltip line says why.
#
# waybar reads text and tooltip as Pango markup, and a session's label, agent and detail are text
# an agent chose, so each is cleaned of control characters, clipped and escaped before it is shown.

def glyph: "󰚩";                              # nf-md-robot
# Control characters and line separators become a space. Format characters (bidi overrides,
# zero-width and tag characters) draw nothing or reorder what is around them, so a command could
# read other than it is, and are dropped.
def clean: gsub("[[:cntrl:]\\p{Zl}\\p{Zp}]"; " ") | gsub("\\p{Cf}"; "");
def clip(n): if length > n then .[0:n] + "…" else . end;
def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
def safe(n): tostring | clean | clip(n) | esc;
# A view's ages are measured when it was made, and the bar shows the line until the next change, so
# a duration would stand still while time passed. The moment the session entered its state does
# not: today's time, else with the day.
def since:
  (now - (. / 1000)) as $t
  | if ($t | strflocaltime("%F")) == (now | strflocaltime("%F"))
    then $t | strflocaltime("%H:%M")
    else $t | strflocaltime("%a %H:%M") end;
def who:
  if .key.process then "pid \(.key.process.pid)"
  elif .key.tmux then "tmux \(.key.tmux.pane)"
  else (.key.opaque // "") end;
def stranded: .state == "waiting" and ((.key.process.pid // -1) as $p | $stranded | index($p) != null);
def rank: if stranded then 2 else {"waiting": 0, "running": 1, "idle": 2}[.state] // 3 end;
def name:
  (if (.label // "") != "" then .label | safe(60)
   else "\(.agent // "agent" | safe(20)) \(who | safe(40))" end)
  + (if .detached then " (background job)" else "" end);
def line:
  "\(name) · \(.state | safe(10)) since \(.ageMs | since)"
  + (if (.detail // "") != "" then "\n  " + (.detail | safe(80)) else "" end)
  + (if stranded then "\n  no window to answer it in" else "" end);

# The number is the sessions in the leading state, out of all of them when others differ, so that
# "1/2" reads as one of two needing you and a bare number means every session is alike.
def count($c; $n): if $c == $n then ($c | tostring) else "\($c)/\($n)" end;

(.sessions // []) as $all
| ($all | map(select(stranded | not))) as $live
| ($live | map(select(.state == "waiting")) | length) as $w
| ($live | map(select(.state == "running")) | length) as $r
| ($all | length) as $n
| (if $w > 0 then "waiting" elif $r > 0 then "running" elif $n > 0 then "idle" else "none" end) as $state
| ($all | sort_by(rank)) as $ss
| if (.version // 1) != 1 then
    {class: "down", text: (glyph + " ✕"), tooltip: "unsupported agent view version \(.version | safe(10))"}
  elif (.agg.state // "") == "down" then
    {class: "down", text: (glyph + " ✕"), tooltip: "the agent source is not running"}
  else {
    class: $state,
    text: (
      if $state == "none" then glyph
      else glyph + " " + count(
        (if $state == "waiting" then $w elif $state == "running" then $r else ($n - $w - $r) end); $n)
      end),
    tooltip: (($ss[0:12] | map(line) | join("\n"))
      + (if ($ss | length) > 12 then "\n…and \(($ss | length) - 12) more" else "" end))
  } end
