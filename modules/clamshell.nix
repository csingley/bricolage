# Clamshell policy (docs/clamshell.md; the script is scripts/clamshell.sh): reconciles the internal
# panel on the lid switch, on sway output events and on resume.
#
# Requires (outside Nix):
#   distro sway   - swaymsg
#   base  systemd - systemctl, systemd-run
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./lib.nix { inherit pkgs config; }) scripts;
  clamshell = lib.getExe scripts.clamshell;
in
{
  config = lib.mkIf (config.bricolage.enable && config.bricolage.clamshell.enable) {
    # lid:on (lock, then reconcile) is in default.nix.
    wayland.windowManager.sway.config.bindswitches."lid:off" = {
      locked = true;
      action = "exec ${clamshell} lid-open";
    };

    # Unplugging the last external display with the lid shut fires no lid event.
    systemd.user.services.bricolage-clamshell = {
      Unit = {
        Description = "Bricolage clamshell policy";
        PartOf = [ "sway-session.target" ];
        After = [ "sway-session.target" ];
      };
      Service = {
        ExecStart = "${clamshell} watch";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "sway-session.target" ];
    };

    # The re-lock first: reconcile keeps the panel on while a lock is up, so it should see the one
    # that is there after a crash (idle.nix, scripts/lock.sh). `;` so the reconcile runs even if the
    # re-lock gives up.
    services.swayidle.events.after-resume = "${lib.getExe scripts.lock} after-resume; ${clamshell} reconcile";
  };
}
