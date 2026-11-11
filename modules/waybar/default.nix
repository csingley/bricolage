# The waybar status bar: modules and their settings. Styling is in style.css, the power button's
# popup in power-menu.xml.
#
# Requires (outside Nix):
#   distro sway   - the sway/* modules
#   distro xdg-desktop-portal, xdg-desktop-portal-gtk, xdg-desktop-portal-wlr
#                - restarted before waybar starts (ExecStartPre below)
#   distro power-profiles-daemon - the D-Bus service behind the power-profile widget
#   base  systemd (systemctl) - restarts the portals; power actions are in scripts/power-action.sh
# waybar is a Nix build on a non-NixOS system, so it also needs /usr/share in XDG_DATA_DIRS (see
# tray.nix).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.bricolage;
  w = cfg.bar.widgets;
  # A group of widgets, each present when its switch is on; empty groups are dropped.
  enabledTasks = builtins.attrNames (lib.filterAttrs (_: t: t.enable) cfg.bar.tasks);
  groups = lib.filterAttrs (_: g: g != [ ]) {
    tasks = map (n: "custom/tasks#${n}") enabledTasks;
    energy =
      lib.optional w.battery "battery"
      ++ lib.optional w.powerProfile "power-profiles-daemon"
      ++ lib.optional w.idleInhibitor "idle_inhibitor";
    load =
      lib.optional w.memory "memory"
      ++ lib.optional (w.temperature != null) "temperature"
      ++ lib.optional w.cpu "cpu";
    controls =
      lib.optional w.backlight "backlight"
      ++ lib.optional w.microphone "pulseaudio#mic"
      ++ lib.optional w.speaker "pulseaudio";
  };
  bl = import ../../lib { inherit lib; };
  inherit (import ../lib.nix { inherit pkgs config; }) tools scripts;
  ic = import ./icons.nix {
    inherit lib;
    colors = cfg.colors;
    inherit (bl) ramp;
  };

  # One widget per enabled task source, grouped like the others.
  taskSettings = lib.genAttrs (map (n: "custom/tasks#${n}") enabledTasks) (
    id:
    {
      return-type = "json";
      exec = cfg.bar.tasks.${lib.removePrefix "custom/tasks#" id}.command;
      restart-interval = 5; # a command that ends is started again
    }
  );

  # The default orientation is "orthogonal", which is vertical on a horizontal bar.
  groupSettings = lib.mapAttrs' (
    name: modules:
    lib.nameValuePair "group/${name}" {
      orientation = "horizontal";
      inherit modules;
    }
  ) groups;

  # The package temperature: the hwmon number changes between boots, so the option names the
  # device and waybar finds the hwmon directory under it.
  temperatureSettings = lib.optionalAttrs (w.temperature != null) {
    temperature = {
      hwmon-path-abs = lib.removeSuffix "/hwmon*/" w.temperature;
      input-filename = "temp1_input"; # the package temperature
      critical-threshold = 85;
      interval = 5;
      format = "${ic.temp} {temperatureC:>3}°C";
      tooltip-format = "CPU temperature";
    };
  };

  # Each menu item runs the power-action script, which confirms destructive ones through a swaynag
  # banner.
  glyph = esc: builtins.fromJSON ''"${esc}"'';
  action = name: "${lib.getExe scripts.powerAction} ${name}";
in
{
  config = lib.mkIf config.bricolage.enable {
    programs.waybar = {
      enable = true;
      systemd.enable = true;
      settings.main =
        groupSettings
        // taskSettings
        // temperatureSettings
        // {
          layer = "top";
          position = "top";
          height = 28;
          # The tray, which is clicked, is first so it stays at the bar's edge; the workspaces, which are
          # driven by keys, shift when it changes width. The mode label, which appears only in a mode such
          # as resize, comes last so it moves nothing.
          modules-left = [
            "tray"
            "sway/workspaces"
            "sway/mode"
          ];
          modules-center = [ "clock" ];
          # Left to right, five groups (gaps in style.css): tasks (sources of work that may need you, if
          # any are enabled), energy (battery and the modes that drain it), load (memory, temperature,
          # cpu), controls (brightness, mic, speaker), power (the session menu). Every widget has a fixed
          # width, so each sits a fixed distance from the right edge; tasks, whose width follows what it
          # reports, is leftmost so that it moves nothing.
          modules-right =
            map (g: "group/${g}") (
              builtins.filter (g: groups ? ${g}) [
                "tasks"
                "energy"
                "load"
                "controls"
              ]
            )
            ++ [ "custom/power" ];
          # Workspaces 1 to `pinned` are always shown (empty ones dimmer), so the picker has a constant
          # width.
          "sway/workspaces" = {
            persistent-workspaces = lib.genAttrs (map toString (lib.range 1 cfg.bar.workspaces.pinned)) (
              _: [ ]
            );
            # The number, then one glyph per window (what is on the workspace, at a glance).
            format = "<b>{name}</b> {windows}";
            # One space between window glyphs: they overflow their cells, so anything narrower overlaps.
            format-window-separator = " ";
            # One glyph per window, by app; terminals share one glyph and windows with no rule get the generic
            # one. Teams and Outlook run in Chrome, so they match on the title.
            window-rewrite = {
              "class<foot>" = glyph "\\uf120"; # terminal
              "class<slack>" = glyph "\\uf198";
              "class<google-chrome>" = glyph "\\uf268";
              "class<firefox.*>" = glyph "\\uf269";
              "class<libreoffice.*>" = glyph "\\uf15c"; # a document
              "class<org.gnome.Papers>" = glyph "\\uf1c1"; # PDF
              "title<.*Microsoft Teams.*>" = glyph "\\udb80\\udebb"; # md-microsoft_teams
              "title<.*Outlook.*>" = glyph "\\udb83\\udd22"; # md-microsoft_outlook
            };
            window-rewrite-default = glyph "\\uf2d0"; # any other window
          };
          cpu = {
            format = "{icon}"; # the exact % is in the tooltip
            format-icons = ic.cpuBars;
            # Averaged over the interval; a longer one is steadier and cheaper.
            interval = 4;
            tooltip-format = "CPU: {usage}% busy, {avg_frequency} GHz\nClick: btop\nRight-click: htop";
            on-click = tools.btop;
            on-click-right = tools.htop;
          };
          memory = {
            format = "${ic.memory} {percentage:>3}%";
            interval = 5;
            # Percent used; style.css colors the classes without a flash: running near full RAM is normal for
            # some workloads and swap absorbs it.
            states = {
              warning = 80;
              critical = 90;
            };
            tooltip-format = "Memory: {used:0.1f} / {total:0.1f} GiB\nClick: btop\nRight-click: htop";
            on-click = tools.btop;
            on-click-right = tools.htop;
          };
          # Scroll over it to change brightness (same tool as the brightness keys).
          backlight = {
            format = "${ic.brightness} {percent:>3}%";
            tooltip-format = "Brightness\nScroll: adjust";
            on-scroll-up = "${tools.brightnessctl} set 5%+";
            on-scroll-down = "${tools.brightnessctl} set 5%-";
          };

          # Click to toggle: the coffee cup holds off idle lock, screen-off and suspend; the moon is the
          # normal policy.
          idle_inhibitor = {
            format = "{icon}";
            format-icons = {
              # The coffee glyph is ~2x its cell and overflows right; the trailing space makes its box as wide
              # as its ink so it centers.
              activated = "${ic.awake} ";
              deactivated = ic.auto;
            };
            tooltip-format-activated = "Keep awake: on\nClick: allow idle";
            tooltip-format-deactivated = "Keep awake: off\nClick: keep awake";
          };

          clock = {
            format = "{:%a %b %d  %H:%M}";
            format-alt = "{:%A, %-d %B %Y  %H:%M}"; # click to toggle
            tooltip-format = "<tt><small>{calendar}</small></tt>";
          };
          tray.spacing = 10;
          pulseaudio = {
            format = "{icon}  {volume:>3}%"; # two spaces: the wide speaker glyph overflows its cell
            # Muted keeps the unmuted width ("--" right-aligned, a trailing space for "%") so the bar
            # doesn't jump.
            format-muted = "${ic.volMute}   -- ";
            # (waybar has no per-mute-state tooltip, so the click line says "toggle mute".)
            # Tooltips: line 1 is "Name: value", then one "Verb: effect" line per action (Click, Scroll,
            # Right-click); read-only widgets show line 1 only.
            tooltip-format = "Speaker: {desc}\nClick: toggle mute\nScroll: volume\nRight-click: mixer";
            format-icons.default = [
              ic.volLow
              ic.volHigh
            ];
            # Scroll over it to change volume (same tool and cap as the volume keys).
            on-scroll-up = "${tools.wpctl} set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 2%+";
            on-scroll-down = "${tools.wpctl} set-volume @DEFAULT_AUDIO_SINK@ 2%-";
            # Click mutes, right-click opens the mixer (same as the mic widget).
            on-click = "${tools.wpctl} set-mute @DEFAULT_AUDIO_SINK@ toggle";
            on-click-right = tools.pavucontrol;
          };
          # Microphone: second pulseaudio instance showing only the default input.
          # Click toggles mute (same as the mic key); scroll changes input volume.
          "pulseaudio#mic" = {
            format = "{format_source}";
            format-source = "${ic.mic} {volume:>3}%";
            format-source-muted = "${ic.micMute}  -- ";
            tooltip-format = "Microphone\nClick: toggle mute\nScroll: volume\nRight-click: mixer";
            on-click = "${tools.wpctl} set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
            on-click-right = "${tools.pavucontrol} --tab=4";
            on-scroll-up = "${tools.wpctl} set-volume -l 1.0 @DEFAULT_AUDIO_SOURCE@ 2%+";
            on-scroll-down = "${tools.wpctl} set-volume @DEFAULT_AUDIO_SOURCE@ 2%-";
          };
          battery = {
            states = {
              warning = 30;
              critical = 15;
            };
            # Two spaces after the icon: the battery glyph is wider than its cell and overflows to
            # the right, so one space leaves it touching the number (as the volume format does).
            format = "{icon}  {capacity:>3}%";
            format-charging = "${ic.charging}  {capacity:>3}%";
            format-plugged = "${ic.plugged}  {capacity:>3}%";
            format-icons = ic.bat;
            # Click: time remaining or until full as "7:17" ({m} is zero-padded minutes; the default
            # "7 h 17 min" is much wider), right-aligned in 4 columns so the pill keeps its width.
            format-time = "{H}:{m}";
            format-alt = "{icon}  {time:>4}";
            format-alt-charging = "${ic.charging}  {time:>4}";
            format-alt-plugged = "${ic.plugged}  {time:>4}";
            tooltip-format = "Battery: {timeTo}\nPower: {power} W\nClick: toggle percentage / time";
            # On AC the click toggle has no visible effect; don't offer it.
            tooltip-format-charging = "Charging: {timeTo}\nPower: {power} W";
            tooltip-format-plugged = "On AC power\nPower: {power} W";
            tooltip-format-full = "Fully charged\nPower: {power} W";
          };
          # System power-profiles-daemon; click cycles performance/balanced/power-saver.
          power-profiles-daemon = {
            format = "{icon}";
            tooltip-format = "Power profile: {profile}\nClick: cycle";
            format-icons = {
              inherit (ic) balanced;
              default = ic.balanced;
              performance = ic.perf;
              power-saver = ic.saver;
            };
          };
          "custom/power" = {
            format = ic.power;
            # A custom module only has a tooltip if its exec supplies one.
            return-type = "json";
            interval = "once";
            exec = "${pkgs.coreutils}/bin/cat ${./power-tooltip.json}";
            menu = "on-click";
            menu-file = "${./power-menu.xml}";
            menu-actions = {
              lock = action "lock";
              suspend = action "suspend";
              logout = action "logout";
              reboot = action "reboot";
              poweroff = action "poweroff";
            };
          };
        };
      # The @define-color lines, then the rules.
      style =
        bl.css cfg.colors
        +
          builtins.replaceStrings [ "__WORKSPACE_WIDTH__" ] [ (toString cfg.bar.workspaces.buttonMinWidth) ]
            (builtins.readFile ./style.css);
    };

    # Portals from the previous sway session survive logout and keep a GTK backend bound to the dead
    # DISPLAY, so waybar blocks ~30 s on the portal's appearance query. Restart them against the new
    # session's environment (imported by sway-session.target).
    systemd.user.services.waybar.Service.ExecStartPre = [
      "-${tools.systemctl} --user restart xdg-desktop-portal-gtk.service xdg-desktop-portal.service"
    ];
  };
}
