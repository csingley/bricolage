# The `bricolage` options: what differs between machines. The defaults are the portable ones; a
# host file sets what its machine needs.
{ config, lib, ... }:
let
  bl = import ../lib { inherit lib; };
in
{
  options.bricolage = {
    enable = lib.mkEnableOption "the Bricolage desktop";

    colors = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = bl.defaults;
      defaultText = lib.literalMD "a neutral dark palette";
      example = lib.literalExpression ''
        {
          bg = "#1e1e2e";
          surface = "#313244";
          surface_subtle = "#181825";
          selection = "#45475a";
          border = "#585b70";
          fg_faint = "#6c7086";
          fg_subtle = "#7f849c";
          fg_muted = "#bac2de";
          fg = "#cdd6f4";
          error = "#f38ba8";
          warning = "#f9e2af";
          success = "#a6e3a1";
          accent = "#89b4fa";
          special = "#f5c2e7";
          string = "#a6e3a1";
        }
      '';
      description = ''
        The colors Bricolage draws with, as `#rrggbb` strings under these names: ${lib.concatStringsSep ", " bl.required}.
        Extra names are passed through to the stylesheets. Any theme can supply them: a theme
        module's own roles if they use these names, a mapping in your own config, or
        `bricolage.lib.fromBase16` for a Base16 scheme.
      '';
    };

    btop.colorTheme = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "my-theme";
      description = ''
        The btop theme to select, for a theme that ships a btop theme file but doesn't set btop's
        config itself. null leaves `color_theme` to a theme module (or btop's own default).
      '';
    };

    htop.colorsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression ''"''${malachite.portFile "htop" "osc"}"'';
      description = ''
        A file of terminal color escape sequences, printed in the htop window before htop starts (htop
        draws with the terminal's colors); null leaves the terminal's own colors.
      '';
    };

    wallpaper = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/usr/share/backgrounds/wallpaper.jpg";
      description = ''
        The image sway paints, and gtklock blurs for the lock screen. null leaves the desktop the
        the `bg` color and the lock screen a plain color.
      '';
    };

    # A convenience bundle, not a switch the modules read directly: it sets the default of the
    # battery, power-profile and brightness widgets and of suspend-on-battery. Any of those can be
    # set on its own and wins over the bundle (laptop = true plus widgets.backlight = false is a
    # laptop without the brightness widget).
    laptop = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        This machine has a battery and a backlight. Sets the default of
        `bar.widgets.{battery,powerProfile,backlight}` and `idle.suspendOnBattery`.
      '';
    };

    idle.suspendOnBattery = lib.mkOption {
      type = lib.types.bool;
      default = config.bricolage.laptop;
      defaultText = lib.literalExpression "config.bricolage.laptop";
      description = "Suspend after a long idle when running on battery (never on AC).";
    };

    clamshell.enable = lib.mkEnableOption ''
      the clamshell policy (docs/clamshell.md): the internal panel is off while the lid is closed
      and another display is active, and on otherwise. It does not depend on a layout tool
    '';

    bar = {
      workspaces = {
        pinned = lib.mkOption {
          type = lib.types.ints.unsigned;
          default = 4;
          description = ''
            Workspaces 1 to N are always shown, empty ones included (styled dimmer), so the
            picker has a constant width and the tray after it never moves. 0 shows only the
            workspaces in use.
          '';
        };
        buttonMinWidth = lib.mkOption {
          type = lib.types.ints.positive;
          default = 84;
          description = ''
            The minimum width of a workspace button, in logical pixels. Wide enough for the
            number and about three window glyphs; the buttons are all this wide so the bar does
            not shift. Narrower screens need less (about 64 at 1536 px). A button with more
            windows than fit grows.
          '';
        };
      };

      # One switch per widget. A group left with no widgets disappears from the bar.
      widgets =
        let
          widget =
            default: description:
            lib.mkOption {
              type = lib.types.bool;
              inherit default description;
            };
        in
        {
          battery = widget config.bricolage.laptop "Charge, and time left (click).";
          powerProfile = widget config.bricolage.laptop "power-profiles-daemon's profile (click cycles).";
          idleInhibitor = widget true "Keep-awake toggle: holds off the idle lock, screen-off and suspend.";
          memory = widget true "Memory use.";
          temperature = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = "/sys/devices/platform/coretemp.0/hwmon/hwmon*/";
            example = "/sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon*/";
            description = ''
              The CPU temperature widget: the sensor's hwmon device directory, ending in
              `hwmon*/` (the number changes between boots), or null for no widget. The widget
              reads `temp1_input`, the package temperature on both vendors (Intel "Package id 0",
              AMD Tctl). The default is Intel's coretemp device, the same on every Intel machine.
              AMD's k10temp device is under the PCI bus, so its address depends on the chipset
              (the example is typical for a Ryzen laptop; `host-probe.sh` prints the real one).
              A path that does not exist makes waybar quietly show some other sensor, so set this
              on each new machine.
            '';
          };
          cpu = widget true "CPU load gauge.";
          backlight = widget config.bricolage.laptop "Screen brightness (scroll).";
          microphone = widget true "Microphone level and mute.";
          speaker = widget true "Speaker volume and mute.";
        };
    };

    # Sources of tasks: one widget each, in a pill of their own. See the description.
    bar.tasks = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "this task source's widget";
            command = lib.mkOption {
              type = lib.types.str;
              example = lib.literalExpression ''"''${pkgs.writeShellScript "bells" "..."}"'';
              description = "The command that reports the tasks; it runs for as long as the bar does.";
            };
          };
        }
      );
      default = { };
      example = lib.literalExpression ''{ bells = { enable = true; command = "''${bellWatcher}"; }; }'';
      description = ''
        Sources of tasks: work that runs on its own and may need you, such as agent sessions, builds,
        CI runs, backups or a pane that rang its bell. Each enabled source is a widget, named by its
        attribute, in a pill at the left of the bar's right side, so that the pill's width changing
        moves nothing else.

        The command prints one JSON object per line, in waybar's custom-module format, each time
        its report changes: `{"text": "...", "class": "...", "tooltip": "..."}`. Any command that
        already works as a waybar custom module qualifies. `text` and `tooltip` are Pango markup, so
        the command must escape anything it did not write itself, and `text` should not be empty.
        The `class` is one of the following, and sets the widget's look:

        - `none`: no tasks. Faint.
        - `idle`: tasks exist and none is running or waiting. The plain text color.
        - `running`: work is in progress. Green.
        - `waiting`: a task is blocked on you. A flashing amber fill, which is a call to act.
        - `down`: the source cannot be reached, which is not the same as no tasks. Red text,
          asking for nothing.

        A source's name is added as a second CSS class, and must be lowercase letters, digits and
        hyphens.
      '';
    };

    polkitAgent = lib.mkOption {
      type = lib.types.str;
      default = "/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1";
      example = "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1";
      description = ''
        The distro's polkit authentication agent. Its path differs between distros: Debian and Ubuntu
        (the default), `/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1` on Arch,
        `/usr/libexec/polkit-gnome-authentication-agent-1` on Fedora.
      '';
    };

    terminal.shell = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/usr/bin/zsh";
      description = "The shell foot starts. null starts the login shell.";
    };

    terminal.opacity = lib.mkOption {
      type = lib.types.numbers.between 0.0 1.0;
      default = 1.0;
      example = 0.95;
      description = "The terminal's background opacity, 0 to 1; only the background is see-through.";
    };
  };

  config.assertions = lib.mkIf config.bricolage.enable [
    {
      assertion = lib.all (n: config.bricolage.colors ? ${n}) bl.required;
      message = "bricolage.colors lacks: ${
        lib.concatStringsSep ", " (lib.filter (n: !(config.bricolage.colors ? ${n})) bl.required)
      }.";
    }
    {
      assertion = lib.all (n: builtins.match "[a-z][a-z0-9-]*" n != null) (
        builtins.attrNames config.bricolage.bar.tasks
      );
      message = "bricolage.bar.tasks names must be lowercase letters, digits and hyphens, starting with a letter.";
    }
    {
      assertion =
        config.bricolage.bar.widgets.temperature == null
        || lib.hasSuffix "/hwmon*/" config.bricolage.bar.widgets.temperature;
      message = "bricolage.bar.widgets.temperature must end in \"/hwmon*/\" (or be null).";
    }
  ];
}
