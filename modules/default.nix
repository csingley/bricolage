# Requires (outside Nix):
#   distro sway  - the session entry for the display manager (checkConfig is off: the config
#                  can't be validated against a Nix-built sway)
#   base  systemd (loginctl) - the lock keybinding and lid switch
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.bricolage;
  mod = "Mod4";
  bl = import ../lib { inherit lib; };

  inherit (import ./lib.nix { inherit pkgs config; })
    tools
    scripts
    menu
    terminal
    ;

  # The colors as "#rrggbb" and as "rrggbb".
  c = cfg.colors;
  bare = lib.mapAttrs (_: bl.hex) c;
  # j4-dmenu-desktop over the desktop entries, with the menu (lib.nix) as its chooser; text that
  # matches nothing runs as a command.
  launcher = pkgs.writeShellScript "launcher" ''
    exec ${pkgs.j4-dmenu-desktop}/bin/j4-dmenu-desktop --dmenu=${lib.getExe menu} \
      --term=${terminal.bin} --no-generic \
      --usage-log="''${XDG_CACHE_HOME:-$HOME/.cache}/j4-dmenu-desktop.usage"
  '';
in
{
  imports = [
    ./options.nix
    ./idle.nix
    ./clamshell.nix
    ./gtklock
    ./btop.nix
    ./waybar
    ./tray.nix
    ./polkit.nix
    ./ranger.nix
  ];

  config = lib.mkIf config.bricolage.enable {
    # The Wayland session services (waybar, swayidle, ...) run only under sway, not GNOME.
    wayland.systemd.target = "sway-session.target";

    wayland.windowManager.sway = {
      enable = true;
      package = null; # sway comes from the distro
      checkConfig = false; # not validatable against a Nix-built sway
      systemd.enable = true;

      config = {
        modifier = mod;
        terminal = terminal.bin;
        # $mod+d: the fzf launcher.
        menu = "${launcher}";
        bars = [ ]; # waybar runs as a systemd user service

        input = {
          # Caps Lock acts as Escape; Shift+Caps Lock is the real Caps Lock.
          "type:keyboard".xkb_options = "caps:escape_shifted_capslock";
          "type:touchpad" = {
            tap = "enabled";
            natural_scroll = "enabled";
            dwt = "enabled";
          };
        };

        # Zoom to fill; the color shows only where the picture doesn't cover.
        output."*".bg = if cfg.wallpaper != null then "${cfg.wallpaper} fill ${c.bg}" else c.bg;

        # Window colors from bricolage.colors, at default priority so a theme's own sway colors
        # win. The focused window has a surface title bar and brighter text; unfocused windows a bg
        # title bar and a surface border; an urgent window is the error color.
        colors =
          let
            w = border: background: text: indicator: childBorder: {
              inherit border background text indicator childBorder;
            };
          in
          lib.mkDefault {
            focused = w c.border c.surface c.fg c.fg_muted c.border;
            focusedInactive = w c.selection c.surface_subtle c.fg_muted c.selection c.selection;
            unfocused = w c.surface c.bg c.fg_subtle c.surface c.surface;
            urgent = w c.error c.error c.bg c.error c.error;
            placeholder = w c.selection c.bg c.fg_muted c.selection c.selection;
            background = c.bg;
          };

        # Title bars use the bar's font.
        fonts = {
          names = [ "JetBrainsMono Nerd Font" ];
          size = 9.0;
        };
        # Click to focus: under hover-focus, popups that close on losing focus vanish when the
        # pointer crosses a terminal.
        focus.followMouse = "no";

        # Utility windows opened from the bar or tray float, centered, instead of tiling; real
        # dialogs already float.
        window.commands = [
          {
            criteria.app_id = "^(org.pulseaudio.pavucontrol|blueman-manager|nm-connection-editor|nm-applet)$";
            command = "floating enable, resize set width 640 px height 520 px, move position center";
          }
          {
            # the system monitors opened from the CPU and memory pills
            criteria.app_id = "^sysmon-(btop|htop)$";
            command = "floating enable, resize set width 1280 px height 800 px, move position center";
          }
          {
            criteria.app_id = "^launcher$";
            command = "floating enable, resize set width 640 px height 420 px, move position center";
          }
        ];

        keybindings = lib.mkOptionDefault {
          "${mod}+Ctrl+l" = "exec ${tools.loginctl} lock-session";
          "${mod}+Shift+p" = "exec ${lib.getExe scripts.powerMenu}";
          "Print" = "exec ${lib.getExe scripts.screenshot}";

          "--locked XF86AudioRaiseVolume" = "exec ${tools.wpctl} set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+";
          "--locked XF86AudioLowerVolume" = "exec ${tools.wpctl} set-volume @DEFAULT_AUDIO_SINK@ 5%-";
          "--locked XF86AudioMicMute" = "exec ${tools.wpctl} set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
          "--locked XF86AudioMute" = "exec ${tools.wpctl} set-mute @DEFAULT_AUDIO_SINK@ toggle";
          "--locked XF86MonBrightnessUp" = "exec ${tools.brightnessctl} set 5%+";
          "--locked XF86MonBrightnessDown" = "exec ${tools.brightnessctl} set 5%-";
        };

        # Lock when the lid closes (logind then suspends; swayidle locks before sleep too), then
        # apply the clamshell policy if it is on.
        bindswitches."lid:on" = {
          locked = true;
          action = lib.concatStringsSep "; " (
            [ "exec ${tools.loginctl} lock-session" ]
            ++ lib.optional cfg.clamshell.enable "exec ${lib.getExe scripts.clamshell} reconcile"
          );
        };

        # A sway reload resets the output layout; kanshi applies its profile again.
        startup = lib.optional config.services.kanshi.enable {
          command = "${config.services.kanshi.package}/bin/kanshictl reload";
          always = true;
        };

        # No blanket `inhibit_idle fullscreen`: a forgotten fullscreen window would block lock,
        # screen-off and suspend. Video apps set their own inhibitors; add a narrow rule for one that
        # doesn't.
      };
    };

    # The package's mako.service is not found: the user systemd manager does not search
    # ~/.nix-profile/share for units, so D-Bus activation fails. It is defined here instead and
    # started with the sway session; under GNOME, gnome-shell owns notifications.
    systemd.user.services.mako = {
      Unit = {
        Description = "Lightweight Wayland notification daemon";
        PartOf = [ "sway-session.target" ];
        After = [ "sway-session.target" ];
      };
      Service = {
        Type = "dbus";
        BusName = "org.freedesktop.Notifications";
        ExecStart = lib.getExe pkgs.mako;
        ExecReload = "${pkgs.mako}/bin/makoctl reload";
      };
      Install.WantedBy = [ "sway-session.target" ];
    };

    # Shape only; the colors are the theme's.
    services.mako = {
      enable = true;
      settings = {
        font = "JetBrainsMono Nerd Font 10";
        border-size = 2;
        border-radius = 8; # the bar's pill radius
      };
    };

    # swaynag: the banner behind the waybar power menu (`-t warning`) and sway's config errors
    # (`error`); the warning is a surface with a red edge, since it confirms something destructive.
    # There is no `button-border=<color>`: swaynag parses it as a prefix of `--button-border-size` and
    # the hex digits become a huge thickness.
    xdg.configFile."swaynag/config".text = ''
      font=JetBrainsMono Nerd Font 9

      [warning]
      background=${bare.surface}
      text=${bare.fg}
      border=${bare.selection}
      border-bottom=${bare.error}
      button-background=${bare.selection}
      button-text=${bare.fg}

      [error]
      background=${bare.error}
      text=${bare.bg}
      border=${bare.error}
      border-bottom=${bare.bg}
      button-background=${bare.bg}
      button-text=${bare.fg}
    '';

    programs.foot = {
      enable = true;
      settings = {
        main = {
          font = "JetBrainsMono Nerd Font:size=11";
          term = "xterm-256color"; # avoid missing `foot` terminfo on remote hosts
        }
        // lib.optionalAttrs (cfg.terminal.shell != null) { shell = cfg.terminal.shell; };
        # Only the background is translucent, and foot is the only window made see-through; the
        # colors are the theme's.
        colors-dark.alpha = builtins.toJSON cfg.terminal.opacity;
      };
    };

    fonts.fontconfig.enable = true;
    home.packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      brightnessctl
      # Just wpctl, not the wireplumber package: its share/wireplumber would sit ahead of /usr/share
      # in XDG_DATA_DIRS and crash the system's older daemon.
      (pkgs.runCommand "wpctl" { } ''
        mkdir -p $out/bin
        ln -s ${pkgs.wireplumber}/bin/wpctl $out/bin/wpctl
      '')
      grim
      slurp
      wl-clipboard
      pavucontrol
    ];
  };
}
