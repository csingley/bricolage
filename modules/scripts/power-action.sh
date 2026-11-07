# shellcheck shell=bash
# Run a power action. Destructive ones confirm first, through a clickable swaynag
# banner (the mouse path, used by the waybar power menu); `--yes` skips that for
# callers that already asked (scripts/power-menu.sh confirms in the menu).
# Usage: power-action [--yes] lock|suspend|logout|reboot|poweroff
#
# Requires (outside Nix):
#   distro sway   - swaymsg, swaynag
#   base  systemd - loginctl, systemctl
yes=0
if [ "${1-}" = "--yes" ]; then
  yes=1
  shift
fi
case "${1-}" in
  lock)     exec /usr/bin/loginctl lock-session ;;
  suspend)  exec /usr/bin/systemctl suspend ;;
  logout)   cmd=(/usr/bin/swaymsg exit);           msg="End this Sway session?"; label="Log out" ;;
  reboot)   cmd=(/usr/bin/systemctl reboot);       msg="Reboot the machine?";    label="Reboot" ;;
  poweroff) cmd=(/usr/bin/systemctl poweroff);     msg="Power off the machine?"; label="Power off" ;;
  *)
    echo "usage: power-action [--yes] lock|suspend|logout|reboot|poweroff" >&2
    exit 2
    ;;
esac
if [ "$yes" = 1 ]; then
  exec "${cmd[@]}"
fi
exec /usr/bin/swaynag -t warning -m "$msg" -B "$label" "${cmd[*]}"
