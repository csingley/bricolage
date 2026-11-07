# The colors Bricolage draws with: the names it reads, a neutral default palette, and an adapter from
# Base16.
{ lib, color }:
let
  inherit (color) mix;
  norm = h: lib.toLower (if lib.hasPrefix "#" h then h else "#" + h);
in
{
  required = [
    "bg"
    "surface"
    "surface_subtle"
    "selection"
    "border"
    "fg_faint"
    "fg_subtle"
    "fg_muted"
    "fg"
    "error"
    "warning"
    "success"
    "accent"
    "special"
    "string"
  ];

  defaults = {
    bg = "#14161a";
    surface = "#1e2127";
    surface_subtle = "#191c21";
    selection = "#2c313a";
    border = "#3a404b";
    fg_faint = "#5c6370";
    fg_subtle = "#8a919d";
    fg_muted = "#aab1bd";
    fg = "#dcdfe4";
    error = "#e5534b";
    warning = "#d9a441";
    success = "#57ab5a";
    accent = "#539bf5";
    special = "#39c5cf";
    string = "#8ac47f";
  };

  # `@define-color` lines for GTK CSS, one per color.
  css = colors: lib.concatMapStrings (n: "@define-color ${n} ${colors.${n}};\n") (lib.attrNames colors);

  # Base16 slots (`base00` ... `base0F`, "#" optional) -> the names above.
  fromBase16 =
    slots:
    let
      s = lib.mapAttrs' (k: v: lib.nameValuePair (lib.toLower k) (norm v)) slots;
      c = {
        bg = s.base00;
        surface = s.base01;
        selection = s.base02;
        fg_faint = s.base03;
        fg_muted = s.base04;
        fg = s.base05;
        error = s.base08;
        warning = s.base0a;
        success = s.base0b;
        string = s.base0b;
        special = s.base0c;
        accent = s.base0d;
      };
    in
    c
    // {
      surface_subtle = mix c.bg c.surface 0.1;
      border = mix c.selection c.fg_faint 0.4;
      fg_subtle = mix c.fg_faint c.fg_muted 0.5;
    };
}
