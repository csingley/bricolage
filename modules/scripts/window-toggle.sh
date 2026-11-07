# shellcheck shell=bash
# window-toggle APP_ID COMMAND...: close the window with that app-id if one is open, otherwise run
# COMMAND (which is expected to open one). Makes a bar widget's click a toggle.
#
# Requires (outside Nix):
#   distro sway - swaymsg
app_id=$1
shift
if /usr/bin/swaymsg -t get_tree | jq -e --arg id "$app_id" '.. | objects | select(.app_id? == $id)' >/dev/null; then
  /usr/bin/swaymsg "[app_id=\"$app_id\"] kill" >/dev/null
else
  exec "$@"
fi
