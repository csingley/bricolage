# Bricolage's library: color mixing and ramps, and the Base16 adapter that turns a scheme into the
# colors Bricolage reads.
{ lib }:
let
  color = import ./color.nix { inherit lib; };
  colors = import ./colors.nix { inherit lib color; };
in
{
  inherit (color) mix hex;
  ramp = import ./ramp.nix { inherit lib; inherit (color) mix; };
  inherit (colors)
    required
    defaults
    css
    fromBase16
    ;
}
