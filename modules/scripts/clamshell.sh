# shellcheck shell=bash
# Clamshell policy (docs/clamshell.md): the internal panel is on unless the lid is closed and
# another output is active. Idempotent; the state is recomputed from the lid and the outputs on
# every call. Outside a lid-open event the panel is enabled only when it would be the last display,
# so a layout may keep it off with the lid open.
#   clamshell reconcile        apply the policy once
#   clamshell lid-open         the lid opened: the panel comes on, whatever the layout
#   clamshell watch            reconcile, then again on every sway output event
#   clamshell suspend-if-alone suspend if the lid is closed and the panel is the only output
#
# Requires (outside Nix):
#   distro sway   - swaymsg
#   base  systemd - systemctl, systemd-run; the lid state in /proc/acpi/button/lid
swaymsg=/usr/bin/swaymsg
systemctl=/usr/bin/systemctl
systemd_run=/usr/bin/systemd-run
unit=bricolage-clamshell-suspend
grace=5s # a link retrain or monitor standby must not suspend the machine

lid_closed() { grep -qs closed /proc/acpi/button/lid/*/state; }

outputs=
internal=
others=0
panel_on=false

# The internal panel (eDP, LVDS, DSI), and how many other outputs are active. A blanked output is
# still active; a disabled one is not.
scan() {
  outputs=$($swaymsg -t get_outputs)
  internal=$(jq -r '[.[].name | select(test("^(eDP|LVDS|DSI)"))][0] // empty' <<<"$outputs")
  [ -n "$internal" ] || return 1
  others=$(jq --arg i "$internal" '[.[] | select(.active and .name != $i)] | length' <<<"$outputs")
  panel_on=$(jq -r --arg i "$internal" '.[] | select(.name == $i) | .active' <<<"$outputs")
}

cancel_suspend() { $systemctl --user stop "$unit.timer" 2>/dev/null || true; }

reconcile() {
  local trigger=${1:-}
  exec 9>"${XDG_RUNTIME_DIR:-/tmp}/bricolage-clamshell.lock"
  flock 9
  scan || return 0
  if lid_closed && [ "$others" -gt 0 ]; then
    cancel_suspend
    if [ "$panel_on" = true ]; then $swaymsg output "$internal" disable; fi
  else
    if ! lid_closed; then cancel_suspend; fi
    if [ "$panel_on" != true ] && { [ "$others" -eq 0 ] || [ "$trigger" = lid-open ]; }; then
      $swaymsg output "$internal" enable
      # Unplugged the last display with the lid shut: nothing else will suspend the machine.
      if lid_closed; then
        $systemd_run --user --unit="$unit" --on-active="$grace" "$0" suspend-if-alone
      fi
    fi
  fi
}

suspend_if_alone() {
  scan || return 0
  if lid_closed && [ "$others" -eq 0 ]; then $systemctl suspend; fi
}

case "${1:-}" in
  reconcile) reconcile ;;
  lid-open) reconcile lid-open ;;
  suspend-if-alone) suspend_if_alone ;;
  watch)
    reconcile || true
    $swaymsg -t subscribe -m '["output"]' | while read -r _; do reconcile || true; done
    ;;
  *)
    echo "usage: clamshell reconcile|lid-open|watch|suspend-if-alone" >&2
    exit 2
    ;;
esac
