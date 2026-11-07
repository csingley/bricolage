# Idle policy: lock, then screen off, then suspend (on battery only).
#
# Requires (outside Nix):
#   distro sway    - swaymsg, to switch the screen off and on
#   distro gtklock - the locker, started by scripts/lock.sh
#   base  systemd (systemctl), procps (pgrep) - suspend and the already-locked check
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./lib.nix { inherit pkgs config; }) tools scripts;

  # Idle policy (seconds).
  lockAfter = 300; # lock screen
  screenOffAfter = 330; # screen off (resumes on activity)
  suspendAfter = 900; # suspend -- on battery only

  lock = lib.getExe scripts.lock;
  suspendOnBattery = lib.getExe scripts.suspendOnBattery;
in
{
  config = lib.mkIf config.bricolage.enable {
    services.swayidle = {
      enable = true;
      timeouts = [
        {
          timeout = lockAfter;
          command = lock;
        }
        {
          timeout = screenOffAfter;
          command = "${tools.swaymsg} 'output * power off'";
          resumeCommand = "${tools.swaymsg} 'output * power on'";
        }
      ]
      ++ lib.optional config.bricolage.idle.suspendOnBattery {
        timeout = suspendAfter;
        command = suspendOnBattery;
      };
      events = {
        inherit lock;
        before-sleep = lock;
      };
    };
  };
}
