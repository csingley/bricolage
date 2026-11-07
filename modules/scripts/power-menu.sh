# shellcheck shell=bash
# Power menu ($mod+Shift+p): the keyboard path. Destructive actions are confirmed here in the
# desktop's menu, then run through power-action.
# Needs menu and power-action on PATH (runtimeInputs in lib.nix).
#
# Requires (outside Nix):
#   (none: everything comes from Nix; the actions are in power-action.sh)
choice=$(printf '%s\n' lock suspend logout reboot poweroff | menu -p "power:") || exit 0
case "$choice" in
  lock|suspend) exec power-action "$choice" ;;
  logout|reboot|poweroff)
    [ "$(printf '%s\n' no yes | menu -p "$choice?")" = yes ] || exit 0
    exec power-action --yes "$choice"
    ;;
esac
