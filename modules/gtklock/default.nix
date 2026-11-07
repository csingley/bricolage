# Lock screen (gtklock). Styling lives beside this file.
#
# Requires (outside Nix):
#   distro gtklock     - the system's build, which authenticates through the system's PAM stack;
#                        Nix's libpam can't load every module a PAM stack may use
#   distro bubblewrap  - GTK's image loader execs `bwrap` (PATH workaround: scripts/lock.sh)
#
# bricolage.wallpaper is the image to blur for the lock screen, the same one sway paints; null
# means no blurred background (the plain color from style.css).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  wallpaper = config.bricolage.wallpaper;
  bl = import ../../lib { inherit lib; };

  # Nix's own Python with Pillow, for the wallpaper blur (no system python3 needed).
  python = pkgs.python3.withPackages (ps: [ ps.pillow ]);
in
{
  imports = [ ../programs/gtklock.nix ];

  config = lib.mkIf config.bricolage.enable {
    programs.gtklock = {
      enable = true;
      package = null; # the distro's, for its PAM modules
      settings.main = {
        time-format = "%H:%M";
        date-format = "%A, %B %-d";
      }
      // lib.optionalAttrs (wallpaper != null) {
        background = "${config.home.homeDirectory}/.local/share/gtklock/wallpaper-blur.jpg";
      };
      style = bl.css config.bricolage.colors + builtins.readFile ./style.css;
    };

    # A blurred wallpaper so "locked" is obvious; GTK3 CSS can't blur, so the image is pre-rendered.
    home.activation = lib.optionalAttrs (wallpaper != null) {
      gtklockWallpaper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${python}/bin/python3 -I ${./wallpaper-blur.py} \
          ${wallpaper} \
          ${config.home.homeDirectory}/.local/share/gtklock/wallpaper-blur.jpg \
          || echo "gtklock: wallpaper blur failed (lock still works)"
      '';
    };
  };
}
