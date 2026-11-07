#!/usr/bin/env bash
# Prints the facts a new machine's Bricolage options need (the temperature sensor, the screens).
# Read-only. Run it from inside the sway session (it asks sway about the screens).
#
# Usage: ./host-probe.sh
set -u

section() { printf '\n== %s\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

section "distro"
if [ -r /etc/os-release ]; then . /etc/os-release; echo "$PRETTY_NAME"; fi
uname -r

section "cpu"
if have lscpu; then
  lscpu | grep -E '^(Model name|CPU\(s\)|Thread\(s\) per core|Core\(s\) per socket|Vendor ID):'
fi

section "temperature sensors (the waybar module reads one of these)"
for d in /sys/class/hwmon/hwmon*; do
  [ -r "$d/name" ] || continue
  printf '%s  %s  (%s)\n' "$(cat "$d/name")" "$(readlink -f "$d")" \
    "$(ls "$d" | grep -E '^temp[0-9]+_input$' | head -3 | tr '\n' ' ')"
done

section "battery and backlight (a laptop has both)"
ls /sys/class/power_supply 2>/dev/null | sed 's/^/power_supply: /'
ls /sys/class/backlight 2>/dev/null | sed 's/^/backlight: /'
if have powerprofilesctl; then echo "power-profiles-daemon: $(powerprofilesctl get 2>/dev/null)"; else echo "power-profiles-daemon: not installed"; fi

section "screens (sway)"
if have swaymsg && swaymsg -t get_outputs >/dev/null 2>&1; then
  swaymsg -t get_outputs --raw | python3 -c '
import json, sys
for o in json.load(sys.stdin):
    m = o.get("current_mode") or {}
    r = o["rect"]
    print("%s: %s %s" % (o["name"], o.get("make", ""), o.get("model", "")))
    print("  mode: %sx%s @ %.1f Hz" % (m.get("width"), m.get("height"), (m.get("refresh") or 0) / 1000))
    print("  scale: %s   (logical size %sx%s)" % (o.get("scale"), r["width"], r["height"]))
    print("  physical size: %s mm" % (o.get("physical_size") or "unknown"))
' 2>/dev/null || swaymsg -t get_outputs
else
  echo "(sway is not running here; run this inside the session)"
fi

section "programs the desktop expects (from the distro)"
for p in sway swaymsg swaynag gtklock swaylock blueman-applet nm-applet pavucontrol \
         brightnessctl wpctl grim slurp wl-copy tmux zsh; do
  if have "$p"; then printf 'yes  %s\n' "$p"; else printf 'no   %s\n' "$p"; fi
done
