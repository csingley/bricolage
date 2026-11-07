# shellcheck shell=bash
# Select a screen region and copy it to the clipboard as an image.
# Needs grim, slurp and wl-copy on PATH (runtimeInputs in lib.nix).
#
# Requires (outside Nix):
#   (none: grim, slurp and wl-copy come from Nix)
grim -g "$(slurp)" - | wl-copy
