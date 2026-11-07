# Color arithmetic on "#rrggbb" strings.
{ lib }:
let
  chan = h: i: lib.fromHexString (builtins.substring i 2 h);
  hex2 =
    n:
    let
      s = lib.toLower (lib.toHexString n);
    in
    if builtins.stringLength s < 2 then "0" + s else s;
in
{
  # The color `t` of the way from `a` to `b`, t from 0 to 1.
  mix =
    a: b: t:
    "#"
    + lib.concatMapStrings (
      i: hex2 (builtins.floor ((1 - t) * (chan a i) + t * (chan b i) + 0.5))
    ) [ 1 3 5 ];

  # "#rrggbb" -> "rrggbb", for tools that reject the "#"
  hex = lib.removePrefix "#";
}
