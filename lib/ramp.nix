# `n` colors blended left to right between stops (for a load gauge).
#
#   ramp { stops = [ { at = 0.0; color = c.success; } { at = 0.7; color = c.warning; }
#                    { at = 1.0; color = c.error; } ]; n = 16; }
{ lib, mix }:
{
  stops,
  n ? 16,
}:
let
  colorAt =
    p:
    let
      upper = lib.findFirst (st: st.at >= p) (lib.last stops) stops;
      lower = lib.last ([ (builtins.head stops) ] ++ builtins.filter (st: st.at <= p && st != upper) stops);
      span = upper.at - lower.at;
    in
    if span <= 0 then upper.color else mix lower.color upper.color ((p - lower.at) / span);
in
builtins.genList (i: colorAt (i / (n - 1.0))) n
