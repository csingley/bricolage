# programs.gtklock: the gtklock screen locker. Written in home-manager's style (modeled on
# programs.swaylock) so it can be contributed there; Bricolage imports it for now.
{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.programs.gtklock;
  iniFormat = pkgs.formats.ini { };

  # A module is a package from nixpkgs (gtklock-userinfo-module and friends, which install
  # lib/gtklock/<name>-module.so) or the path of a shared object as a string.
  modulePath =
    m:
    if lib.isDerivation m then
      "${m}/lib/gtklock/${lib.removePrefix "gtklock-" (lib.getName m)}.so"
    else
      m;

  stylePath = "${config.xdg.configHome}/gtklock/style.css";

  settings = lib.filterAttrs (_: section: section != { }) (
    lib.recursiveUpdate cfg.settings {
      main =
        lib.optionalAttrs (cfg.style != null) { style = stylePath; }
        // lib.optionalAttrs (cfg.modules != [ ]) {
          modules = lib.concatMapStringsSep ";" modulePath cfg.modules;
        };
    }
  );
in
{
  options.programs.gtklock = {
    enable = lib.mkEnableOption "gtklock, a GTK-based lockscreen for sway";

    package = lib.mkPackageOption pkgs "gtklock" { nullable = true; } // {
      description = ''
        The gtklock package to install, or `null` to install none.

        Note that PAM must be configured for gtklock to authenticate. The package installed through
        home-manager will *not* be able to unlock the session on a non-NixOS system whose PAM stack
        has modules that Nix's libpam cannot load. On non-NixOS, it is easiest to set this to `null`
        and install gtklock from your distribution's repository.
      '';
    };

    settings = lib.mkOption {
      type = iniFormat.type;
      default = { };
      description = ''
        Configuration written to {file}`$XDG_CONFIG_HOME/gtklock/config.ini`: sections of
        key-value pairs, with gtklock's own options in `main`. See {command}`gtklock --help-config`.
        An empty set (and no `style` or `modules`) writes no file.
      '';
      example = lib.literalExpression ''
        {
          main = {
            idle-hide = true;
            time-format = "%H:%M";
          };
        }
      '';
    };

    style = lib.mkOption {
      type = with lib.types; nullOr (either path lines);
      default = null;
      description = ''
        CSS for the lock screen, written to {file}`$XDG_CONFIG_HOME/gtklock/style.css` and set as
        `main.style`; a path is used as the file.
      '';
      example = ''
        window { background-color: #1e1e2e; }
        #clock-label { color: #cdd6f4; }
      '';
    };

    modules = lib.mkOption {
      type = with lib.types; listOf (either package str);
      default = [ ];
      description = ''
        gtklock modules to load, set as `main.modules`: packages such as
        {var}`pkgs.gtklock-userinfo-module`, or paths of shared objects as strings.
      '';
      example = lib.literalExpression "[ pkgs.gtklock-userinfo-module pkgs.gtklock-powerbar-module ]";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (lib.hm.assertions.assertPlatform "programs.gtklock" pkgs lib.platforms.linux)
    ];

    home.packages = lib.mkIf (cfg.package != null) [ cfg.package ];

    xdg.configFile = {
      "gtklock/config.ini" = lib.mkIf (settings != { }) {
        source = iniFormat.generate "gtklock-config.ini" settings;
      };
      "gtklock/style.css" = lib.mkIf (cfg.style != null) (
        if lib.isPath cfg.style || lib.isStorePath cfg.style then
          { source = cfg.style; }
        else
          { text = cfg.style; }
      );
    };
  };
}
