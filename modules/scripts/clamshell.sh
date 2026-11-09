# shellcheck shell=bash
# Clamshell policy (docs/clamshell.md): the internal panel is on unless the lid is closed and
# another output is active. Idempotent; the state is recomputed from the lid and the outputs on
# every call. Outside a lid-open event the panel is enabled only when it would be the last display,
# so a layout may keep it off with the lid open.
#
# While another display is active the script holds a lid-switch inhibitor, so logind does not
# suspend (its HandleLidSwitchDocked may be "suspend"); without one, logind's own lid action applies.
# gtklock crashes when its output is disabled, so the panel is left on while a lock is up and the
# script retries until it is gone.
#   clamshell reconcile        apply the policy once
#   clamshell lid-close        the lid closed: apply the policy; lock if the panel is the last display
#   clamshell lid-open         the lid opened: the panel comes on, whatever the layout
#   clamshell watch            reconcile, then again on every sway output event
#   clamshell suspend-if-alone lock, then suspend, if the lid is closed and the panel is the only output
#
# Requires (outside Nix):
#   distro sway   - swaymsg
#   base  systemd - systemctl, systemd-run; the lid state in /proc/acpi/button/lid
swaymsg=/usr/bin/swaymsg
loginctl=/usr/bin/loginctl
pgrep=/usr/bin/pgrep
systemctl=/usr/bin/systemctl
systemd_run=/usr/bin/systemd-run
unit=bricolage-clamshell-suspend
retry_unit=bricolage-clamshell-retry
inhibit_unit=bricolage-clamshell-inhibit
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

hold_inhibitor() {
  if ! $systemctl --user --quiet is-active "$inhibit_unit.service"; then
    $systemd_run --user --quiet --unit="$inhibit_unit" /usr/bin/systemd-inhibit \
      --what=handle-lid-switch --who=bricolage-clamshell --why="a display is attached" \
      /usr/bin/sleep infinity || true
  fi
}

release_inhibitor() { $systemctl --user stop "$inhibit_unit.service" 2>/dev/null || true; }

cancel_suspend() { $systemctl --user stop "$unit.timer" 2>/dev/null || true; }

# One reconcile at a time; the lock is held only for its subshell.
reconcile() { (flock 9; reconcile_locked "${1:-}") 9>"${XDG_RUNTIME_DIR:-/tmp}/bricolage-clamshell.lock"; }

reconcile_locked() {
  local trigger=$1
  scan || return 0
  # Released only with the lid open: dropping it under a closed lid makes logind suspend at once,
  # before the grace delay and the lock.
  if [ "$others" -gt 0 ]; then
    hold_inhibitor
  elif ! lid_closed; then
    release_inhibitor
  fi
  if lid_closed && [ "$others" -gt 0 ]; then
    cancel_suspend
    if [ "$panel_on" = true ]; then
      if "$pgrep" -x gtklock >/dev/null; then
        $systemd_run --user --quiet --unit="$retry_unit" --on-active=10s "$0" reconcile || true
      else
        $swaymsg output "$internal" disable
      fi
    fi
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

# Lock first and wait for the locker, so the panel never wakes showing the session.
suspend_if_alone() {
  scan || return 0
  if lid_closed && [ "$others" -eq 0 ]; then
    "$pgrep" -x gtklock >/dev/null || $loginctl lock-session
    for _ in 1 2 3 4 5 6 7 8; do
      "$pgrep" -x gtklock >/dev/null && break
      /usr/bin/sleep 0.5
    done
    /usr/bin/sleep 1 # gtklock -d detaches once locked; leave it a moment
    $systemctl suspend
  fi
}

case "${1:-}" in
  reconcile) reconcile ;;
  lid-open) reconcile lid-open ;;
  lid-close)
    reconcile
    scan || true
    if [ "$others" -eq 0 ]; then $loginctl lock-session; fi
    ;;
  suspend-if-alone) suspend_if_alone ;;
  watch)
    reconcile || true
    $swaymsg -t subscribe -m '["output"]' | while read -r _; do reconcile || true; done
    ;;
  *)
    echo "usage: clamshell reconcile|lid-open|lid-close|watch|suspend-if-alone" >&2
    exit 2
    ;;
esac
