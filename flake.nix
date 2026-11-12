{
  description = "Bricolage: a minimal, hand-assembled desktop environment on sway";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    # only for the module checks
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The current stable release.
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-26.05";
    home-manager-stable = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      nixpkgs,
      ...
    }:
    let
      bricolage = import ./. { inherit (nixpkgs) lib; };

      # The module built into a real home-manager configuration, with `colors` if given, and a check
      # of the generated files.
      moduleCheck =
        {
          pkgs,
          home-manager ? inputs.home-manager,
          colors ? null,
          extra ? { },
          expect,
        }:
        let
          hm = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              self.homeModules.default
              {
                home = {
                  username = "test";
                  homeDirectory = "/home/test";
                  stateVersion = "24.11";
                };
                nixpkgs.config.allowUnfree = true;
                bricolage.enable = true;
              }
              (pkgs.lib.optionalAttrs (colors != null) { bricolage.colors = colors; })
              extra
            ];
          };
        in
        pkgs.runCommand "bricolage-module-check" { } ''
          cd ${hm.config.home-files}
          must() { grep -q "$@" || { echo "missing: $*"; exit 1; }; }
          mustnt() { if grep -q "$@"; then echo "unexpected: $*"; exit 1; fi; }
          absent() { if test -e "$1"; then echo "unexpected: $1"; exit 1; fi; }
          test -e .config/sway/config
          test -e .config/waybar/config
          test -e .config/gtklock/style.css
          must '^style=/home/test/.config/gtklock/style.css' .config/gtklock/config.ini
          must '^time-format=%H:%M' .config/gtklock/config.ini
          test -e .config/swaynag/config
          must '^theme_background = False' .config/btop/btop.conf
          ${expect}
          touch $out
        '';
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      flake = {
        inherit (bricolage) lib;
        homeModules.default = ./modules;
      };

      perSystem =
        { pkgs, ... }:
        {
          # The built-in palette, a palette written out by hand, and a Base16 scheme.
          checks.module-default = moduleCheck {
            inherit pkgs;
            expect = ''
              must '^@define-color bg #14161a;' .config/waybar/style.css
              must '^client.focused #3a404b #1e2127 #dcdfe4 #aab1bd #3a404b' .config/sway/config
              must '^swaybg_command /nix/store/.*/bin/swaybg$' .config/sway/config
              # no wallpaper: swaybg paints the bg color
              must '^  bg #14161a solid_color$' .config/sway/config
              mustnt '^color_theme' .config/btop/btop.conf
              # no task sources: no task pills
              mustnt 'custom/tasks' .config/waybar/config
            '';
          };
          # Task sources: the enabled ones share one pill, first on the right, and every class a source
          # may report has a rule (idle is the plain text color).
          checks.module-tasks = moduleCheck {
            inherit pkgs;
            extra.bricolage.bar.tasks = {
              bells = {
                enable = true;
                command = "/bin/true";
                onClick = "/bin/echo clicked";
              };
              builds = {
                enable = true;
                command = "/bin/true";
              };
              off.command = "/bin/true"; # defined, not enabled
            };
            expect = ''
              must '"custom/tasks#bells": {' .config/waybar/config
              must '"custom/tasks#builds": {' .config/waybar/config
              mustnt 'custom/tasks#off' .config/waybar/config
              # a click action goes to the source that set it, and only to that one
              grep -A4 '"custom/tasks#bells": {' .config/waybar/config | grep -q '"on-click": "/bin/echo clicked"'
              if grep -A4 '"custom/tasks#builds": {' .config/waybar/config | grep -q on-click; then echo 'unexpected on-click on builds'; exit 1; fi
              # one pill for the sources, first on the right
              grep -A2 '"modules-right"' .config/waybar/config | tr -d ' \n' | grep -q '^"modules-right":\["group/tasks","group/'
              grep -A5 '"group/tasks": {' .config/waybar/config | tr -d ' \n' | grep -q '"modules":\["custom/tasks#bells","custom/tasks#builds"\]'
              must '^#tasks, #energy, #load, #controls { background: @surface;' .config/waybar/style.css
              for c in none running waiting down; do must "^#custom-tasks\.$c " .config/waybar/style.css; done
              must '^@keyframes warning-flash' .config/waybar/style.css
            '';
          };
          # The agent-sessions widget is a task source of its own, with a click action.
          checks.module-agents = moduleCheck {
            inherit pkgs;
            extra.bricolage.bar.agents = {
              enable = true;
              watchCommand = "/bin/true watch";
              listCommand = "/bin/true list";
            };
            expect = ''
              must '"custom/tasks#agents": {' .config/waybar/config
              grep -A4 '"custom/tasks#agents": {' .config/waybar/config | grep -q '"exec": "/nix/store/.*-agents-bar"'
              grep -A4 '"custom/tasks#agents": {' .config/waybar/config | grep -q '"on-click": "/nix/store/.*-agents-focus"'
              # the widget's width comes from its text, which is the same length in every state
              # (tests/agents.sh), so the stylesheet sets none
              mustnt 'custom-tasks\.agents' .config/waybar/style.css
            '';
          };
          # The widget's script and formatter, run against a fake /proc, a fake swaymsg and canned
          # views: what each class looks like, that a waiting session no window holds does not raise
          # the alert, that a click goes to the right window, and that an agent's text cannot reach
          # the bar as markup.
          checks.agents-script =
            let
              agents = pkgs.writeShellApplication {
                name = "agents";
                runtimeInputs = [ pkgs.jq ];
                text = builtins.readFile ./modules/scripts/agents.sh;
              };
            in
            pkgs.runCommand "bricolage-agents-check" { nativeBuildInputs = [ pkgs.jq ]; } ''
              bash ${./tests/agents.sh} ${agents}/bin/agents ${./modules/scripts/agents.jq}
              touch $out
            '';
          # Imported but not enabled: nothing is applied.
          checks.module-disabled =
            let
              hm = inputs.home-manager.lib.homeManagerConfiguration {
                inherit pkgs;
                modules = [
                  self.homeModules.default
                  {
                    home = {
                      username = "test";
                      homeDirectory = "/home/test";
                      stateVersion = "24.11";
                    };
                  }
                ];
              };
            in
            pkgs.runCommand "bricolage-disabled-check" { } ''
              cd ${hm.config.home-files}
              absent() { if test -e "$1"; then echo "unexpected: $1"; exit 1; fi; }
              absent .config/sway/config
              absent .config/waybar/config
              absent .config/gtklock
              touch $out
            '';
          # programs.gtklock on its own: settings, a style and modules.
          checks.gtklock-module =
            let
              hm = inputs.home-manager.lib.homeManagerConfiguration {
                inherit pkgs;
                modules = [
                  ./modules/programs/gtklock.nix
                  {
                    home = {
                      username = "test";
                      homeDirectory = "/home/test";
                      stateVersion = "24.11";
                    };
                    programs.gtklock = {
                      enable = true;
                      settings.main.idle-hide = true;
                      style = "window { background-color: #000000; }";
                      modules = [
                        pkgs.gtklock-userinfo-module
                        "/usr/lib/gtklock/x-module.so"
                      ];
                    };
                  }
                ];
              };
            in
            pkgs.runCommand "gtklock-module-check" { } ''
              cd ${hm.config.home-files}
              grep -q '^idle-hide=true' .config/gtklock/config.ini
              grep -q '^style=/home/test/.config/gtklock/style.css' .config/gtklock/config.ini
              grep -q '^modules=.*/lib/gtklock/userinfo-module.so;/usr/lib/gtklock/x-module.so' .config/gtklock/config.ini
              grep -q 'background-color: #000000' .config/gtklock/style.css
              touch $out
            '';
          # The same, against the current stable release (26.05) of nixpkgs and home-manager.
          checks.module-stable = moduleCheck {
            pkgs = inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
            home-manager = inputs.home-manager-stable;
            expect = "";
          };
          # Any set of the required names works, with no adapter.
          checks.module-colors = moduleCheck {
            inherit pkgs;
            colors = {
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
            };
            expect = ''
              must '^@define-color bg #1e1e2e;' .config/waybar/style.css
              must '^@define-color bg #1e1e2e;' .config/gtklock/style.css
              must '^client.urgent #f38ba8 #f38ba8 #1e1e2e #f38ba8 #f38ba8' .config/sway/config
              # mako's colors belong to the theme, so without one they stay stock
              mustnt '^background-color=' .config/mako/config
              must '^background=313244' .config/swaynag/config
            '';
          };
          checks.module-base16 = moduleCheck {
            inherit pkgs;
            colors = bricolage.lib.fromBase16 {
              base00 = "2e3440";
              base01 = "3b4252";
              base02 = "434c5e";
              base03 = "4c566a";
              base04 = "d8dee9";
              base05 = "e5e9f0";
              base06 = "eceff4";
              base07 = "8fbcbb";
              base08 = "bf616a";
              base09 = "d08770";
              base0A = "ebcb8b";
              base0B = "a3be8c";
              base0C = "88c0d0";
              base0D = "81a1c1";
              base0E = "b48ead";
              base0F = "5e81ac";
            };
            expect = ''
              must '^@define-color bg #2e3440;' .config/waybar/style.css
              must '^@define-color warning #ebcb8b;' .config/waybar/style.css
            '';
          };
        };
    };
}
