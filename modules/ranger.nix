# ranger: the package and an rc.conf over ranger's defaults. Colors are the terminal's ANSI palette
# (set by the theme's foot port), so there is no colorscheme here. rifle.conf is left to ranger's
# defaults: text opens in $EDITOR, everything else in xdg-open.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.bricolage.enable {
    home.packages = [ pkgs.ranger ];

    xdg.configFile."ranger/rc.conf".text = ''
      set show_hidden true
      set vcs_aware true
      set preview_images true
      # foot draws images as sixel; the default, w3m, needs X11.
      set preview_images_method sixel
      set column_ratios 1,3,4
    '';
  };
}
