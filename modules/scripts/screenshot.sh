# shellcheck shell=bash
# Select a screen region; save it to ~/Pictures and copy it to the clipboard.
# Needs grim, slurp and wl-copy on PATH (runtimeInputs in lib.nix).
#
# Requires (outside Nix):
#   (none: grim, slurp and wl-copy come from Nix)
grim -g "$(slurp)" - | tee ~/Pictures/"$(date +%Y%m%dT%H%M%S)".png | wl-copy
