# shellcheck shell=bash
# Run a power action. Destructive ones confirm first, through a clickable swaynag
# banner (the mouse path, used by the waybar power menu); `--yes` skips that for
# callers that already asked (scripts/power-menu.sh confirms in the menu).
# Usage: power-action [--yes] lock|suspend|logout|reboot|poweroff
#
# Requires (outside Nix):
#   distro sway   - swaymsg, swaynag
#   base  systemd - loginctl, systemctl
#   base  procps  - pgrep (suspend waits for the locker)
yes=0
if [ "${1-}" = "--yes" ]; then
  yes=1
  shift
fi
case "${1-}" in
  lock)     exec /usr/bin/loginctl lock-session ;;
  suspend)
    # Lock first and wait for the locker, so the machine never wakes showing the session. (A
    # before-sleep lock covers a suspend that comes from elsewhere; this one makes sure the locker
    # is up before the machine goes down, as clamshell's suspend-if-alone does.)
    /usr/bin/pgrep -x gtklock >/dev/null || /usr/bin/loginctl lock-session
    for _ in 1 2 3 4 5 6 7 8; do
      /usr/bin/pgrep -x gtklock >/dev/null && break
      /usr/bin/sleep 0.5
    done
    /usr/bin/sleep 1 # gtklock -d detaches once locked; leave it a moment
    exec /usr/bin/systemctl suspend
    ;;
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
