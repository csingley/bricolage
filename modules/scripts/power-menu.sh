# shellcheck shell=bash
# Power menu ($mod+Shift+p): the keyboard path. Destructive actions are confirmed here in the
# desktop's menu, then run through power-action.
# Usage: power-menu [lock|suspend|logout|reboot|poweroff]
# Given an action, the list of choices is skipped: that is for a key bound to one action (the
# script's path is bricolage.powerMenu). A destructive action is still confirmed in the menu, by
# keyboard alone: the first line is "no", so Enter by itself cancels.
# Needs menu and power-action on PATH (runtimeInputs in lib.nix).
#
# Requires (outside Nix):
#   (none: everything comes from Nix; the actions are in power-action.sh)
if [ $# -gt 0 ]; then
  choice=$1
  case "$choice" in
    lock|suspend|logout|reboot|poweroff) ;;
    *) echo "usage: power-menu [lock|suspend|logout|reboot|poweroff]" >&2; exit 2 ;;
  esac
else
  choice=$(printf '%s\n' lock suspend logout reboot poweroff | menu -p "power:") || exit 0
fi
case "$choice" in
  lock|suspend) exec power-action "$choice" ;;
  logout|reboot|poweroff)
    [ "$(printf '%s\n' no yes | menu -p "$choice?")" = yes ] || exit 0
    exec power-action --yes "$choice"
    ;;
esac
