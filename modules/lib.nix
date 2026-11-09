# Helpers shared by the modules: tool paths and the shell scripts as executables.
#   inherit (import ./lib.nix { inherit pkgs config; }) tools scripts menu;
#
# Requires (outside Nix):
#   distro sway    - swaymsg
#   distro blueman - blueman-applet
#   base  systemd  - loginctl, systemctl, systemd-run
{
  pkgs,
  config,
}:
let
  colors = config.bricolage.colors;
  htopColors = config.bricolage.htop.colorsFile;
  sessionVars = "${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh";
  # The shell scripts in ./scripts, as executables. They stay plain bash (editor support,
  # shellcheck) with no Nix interpolation: what they need comes from `runtimeInputs` or an absolute
  # /usr/bin path.
  script =
    name: runtimeInputs:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      # writeShellApplication: errexit, nounset, pipefail, and shellcheck at build time.
      text = builtins.readFile (./scripts + "/${name}.sh");
    };
  powerAction = script "power-action" [ ];
  windowToggle = script "window-toggle" [ pkgs.jq ];

  # The menu: the one dmenu-style program, used by the launcher and the power menu. Choices on stdin,
  # the chosen line on stdout; `-p PROMPT` sets the prompt. It is fzf in a small floating foot window,
  # with the theme's fzf options; text that matches nothing comes back as typed (the launcher runs it
  # as a command), and Escape returns nothing.
  c = colors;
  # Runs inside the foot window: the list from $1 through fzf, the answer to $2, the prompt $3. The
  # sway session has no home-manager session variables, so it sources them for the theme's fzf options.
  menuFzf = pkgs.writeShellScript "menu-fzf" ''
    . ${sessionVars}
    ${pkgs.fzf}/bin/fzf --layout=reverse --tiebreak=index --no-info \
      --print-query --prompt="$3" --margin=1,2 <"$1" >"$2"
  '';
  # The terminal: foot is named here and nowhere else in the launching code. `run` is a window
  # with an app-id (the sway rules match it) running a command; `extra` is foot flags.
  terminal = {
    bin = "${pkgs.foot}/bin/foot";
    run =
      appId: cmd: extra:
      "${terminal.bin} --app-id=${appId} ${extra} -e ${cmd}";
  };
  menu = pkgs.writeShellScriptBin "menu" ''
    prompt='# '
    if [ "$1" = -p ]; then prompt="$2 "; fi
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    cat >"$tmp/in"
    ${terminal.run "launcher" menuFzf ""} "$tmp/in" "$tmp/out" "$prompt"
    tail -n 1 "$tmp/out"
  '';
  # htop has no theme files: it draws with the terminal's ANSI colors. The window prints the theme's
  # color escape sequences (`bricolage.htop.colorsFile`) and then runs htop. A heavier font weight
  # reads better on htop's filled bars; the size matches foot's.
  htopWindow = pkgs.writeShellScript "htop-window" ''
    ${pkgs.lib.optionalString (htopColors != null) "cat ${htopColors}"}
    exec ${pkgs.htop}/bin/htop
  '';
  htopFont =
    "-o " + pkgs.lib.escapeShellArg "main.font=JetBrainsMono Nerd Font:style=SemiBold:size=11";
in
{
  inherit menu terminal;

  # Absolute tool paths. sway comes from the distro (see default.nix); the rest is from Nix.
  tools = {
    swaymsg = "/usr/bin/swaymsg";
    loginctl = "/usr/bin/loginctl";
    systemctl = "/usr/bin/systemctl";
    bluemanApplet = "/usr/bin/blueman-applet";
    wpctl = "${pkgs.wireplumber}/bin/wpctl";
    brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
    pavucontrol = "${pkgs.pavucontrol}/bin/pavucontrol";
    # A system monitor in a small floating terminal window (the `sysmon-*` app-id rule in default.nix); clicking again closes it.
    btop = "${windowToggle}/bin/window-toggle sysmon-btop ${terminal.run "sysmon-btop" "${pkgs.btop}/bin/btop" ""}";
    htop = "${windowToggle}/bin/window-toggle sysmon-htop ${terminal.run "sysmon-htop" htopWindow htopFont}";
  };

  scripts = {
    inherit powerAction;
    powerMenu = script "power-menu" [
      menu
      powerAction
    ];
    lock = script "lock" [ ];
    suspendOnBattery = script "suspend-on-battery" [ ];
    clamshell = script "clamshell" [
      pkgs.jq
      pkgs.gnugrep
      pkgs.util-linux
    ];
    screenshot = script "screenshot" [
      pkgs.grim
      pkgs.slurp
      pkgs.wl-clipboard
    ];
  };
}
