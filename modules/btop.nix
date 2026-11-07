# btop: the package and its settings. btop.conf is managed (read-only), so changes made in btop's
# menu don't persist. The theme is a theme module's (one that sets `programs.btop.settings`), or
# `bricolage.btop.colorTheme`.
{
  config,
  lib,
  ...
}:
let
  colorTheme = config.bricolage.btop.colorTheme;
in
{
  config = lib.mkIf config.bricolage.enable {
    programs.btop = {
      enable = true;
      settings = {
        truecolor = lib.mkDefault true;
        show_battery = lib.mkDefault false; # the bar has one
        theme_background = lib.mkDefault false; # so foot's translucency shows through
      }
      // lib.optionalAttrs (colorTheme != null) { color_theme = colorTheme; };
    };
  };
}
