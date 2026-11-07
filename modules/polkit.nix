# Polkit authentication agent: the password dialog for polkit-gated actions (fprintd enrollment,
# pkexec, NetworkManager system settings), started with the sway session. GNOME's shell is its own
# agent.
#
# Requires (outside Nix):
#   distro polkit-gnome - the agent at `bricolage.polkitAgent`. The distro's build, because the
#                         agent authenticates through polkit's setuid helper, which only the
#                         system's polkit provides.
{ config, lib, ... }:
{
  config = lib.mkIf config.bricolage.enable {
    systemd.user.services.polkit-agent = {
      Unit = {
        Description = "Polkit authentication agent";
        PartOf = [ "sway-session.target" ];
        After = [ "sway-session.target" ];
      };
      Service = {
        ExecStart = config.bricolage.polkitAgent;
        Restart = "on-failure";
      };
      Install.WantedBy = [ "sway-session.target" ];
    };
  };
}
