# shellcheck shell=bash
# Suspend only when a battery is discharging: charging / full / on AC => stay up.
# Absolute paths: swayidle's service PATH contains only bash.
#
# Requires (outside Nix):
#   base  systemd - systemctl; grep
/usr/bin/grep -qs '^Discharging$' /sys/class/power_supply/BAT*/status && /usr/bin/systemctl suspend
