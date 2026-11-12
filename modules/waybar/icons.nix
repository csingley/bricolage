# Nerd Font glyph table for the waybar widgets (and the CPU LED gauge).
{
  lib,
  colors,
  ramp,
}:
let
  # Nerd Font glyphs as JSON \u escapes, so the source stays ASCII (codepoints above U+FFFF are
  # surrogate pairs).
  glyph = esc: builtins.fromJSON ''"${esc}"'';
in
{
  # CPU load gauge: an LED-style bar of sixteen thin segments. Colors are fixed by position; a
  # segment is lit in its color or dim, so rising load only adds segments. waybar picks one
  # format-icons entry by usage (100/16 % buckets), so each entry is a whole pre-rendered bar: entry n
  # lights n+1 segments, never fully dark.
  cpuBars =
    let
      # One color per segment, left to right: success to warning (at 70% of the bar) to error. With
      # 16 cores and no SMT, each segment is one more busy core: segment n lights at (n-1)/16 of
      # total usage.
      r = colors;
      gauge = ramp {
        stops = [
          {
            at = 0.0;
            color = r.success;
          }
          {
            at = 0.7;
            color = r.warning;
          }
          {
            at = 1.0;
            color = r.error;
          }
        ];
        n = 16;
      };
      segments = builtins.length gauge;
      segColor = i: builtins.elemAt gauge i;
      dim = r.selection; # an unlit segment
      # Left quarter block: ink is the left quarter of its cell, the rest is the gap. Negative letter
      # spacing (pango units, 1/1024 px) pulls cells together: pitch = advance + spacing. The advance is
      # 8 px (13 px font x 0.6 em, rounded up by hinting), so -3069 (about -3 px) gives a 5 px pitch.
      # FRAGILE: a whole-pixel pitch (5 at 1x, 10 at 2x) keeps every bar on the same pixel phase and
      # crisp; a fractional pitch softens them unevenly. Re-tune if the font, size or hinting changes;
      # fractional output scales (1.25, 1.5) will not be clean.
      seg = glyph "\\u258e";
      spacing = -3069;
      bar =
        lit:
        ''<span letter_spacing="${toString spacing}">''
        + lib.concatStrings (
          lib.genList (i: ''<span color="${if i < lit then segColor i else dim}">${seg}</span>'') segments
        )
        + "</span>";
    in
    map bar (lib.range 1 segments);

  memory = glyph "\\uf2db"; # microchip (fa; reads larger than md-memory U+F035B)
  brightness = glyph "\\uf185"; # sun
  awake = glyph "\\uf0f4"; # coffee
  auto = glyph "\\uf186"; # moon
  volHigh = glyph "\\uf028";
  volLow = glyph "\\uf027";
  volMute = glyph "\\udb81\\udd81"; # md-volume_off U+F0581: the volume glyph struck through, like micMute
  mic = glyph "\\uf130";
  micMute = glyph "\\uf131"; # microphone-slash
  bat = map glyph [
    "\\uf244"
    "\\uf243"
    "\\uf242"
    "\\uf241"
    "\\uf240"
  ]; # empty -> full
  charging = glyph "\\uf0e7"; # bolt
  plugged = glyph "\\uf1e6"; # plug
  power = glyph "\\uf011";
  temp = glyph "\\uf2c9"; # thermometer-half
  agent = glyph "\\udb81\\udea9"; # md-robot U+F06A9, the agent-sessions widget's glyph
  perf = glyph "\\uf135"; # rocket
  balanced = glyph "\\uf24e"; # balance-scale
  saver = glyph "\\uf06c"; # leaf
}
