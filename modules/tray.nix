# Tray applets: network (nm-applet) and Bluetooth (blueman), started with the sway session.
#
# Requires (outside Nix):
#   distro network-manager - nm-applet is only a front end for the system service
#   distro blueman         - tray icon, manager window and pairing agent
#                           (/usr/bin/blueman-applet, started by a unit below)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./lib.nix { inherit pkgs config; }) tools;
in
{
  config = lib.mkIf config.bricolage.enable {
    # nm-applet: signal icon, SSID, switching and VPN, so there is no waybar `network` module. SNI
    # mode so it shows in waybar's tray.
    xsession.preferStatusNotifierItems = true;
    services.network-manager-applet.enable = true;
    # The applet module adds its store path to XDG_DATA_DIRS via environment.d; with no default for
    # that variable it would become the only entry, hiding /usr/share (schemas, icons, sessions) and
    # crashing gnome-shell. The distro directories come from targets.genericLinux. Started only under
    # sway; GNOME has its own.
    systemd.user.services.network-manager-applet = {
      Unit.PartOf = lib.mkForce [ "sway-session.target" ];
      Unit.After = lib.mkForce [
        "sway-session.target"
        "tray.target"
      ];
      Install.WantedBy = lib.mkForce [ "sway-session.target" ];
    };

    # blueman's applet (the distro's) provides the tray icon, manager window and pairing agent. The manager
    # times out without a window if the applet isn't up, and the distro package only D-Bus-activates it
    # slowly, so it starts with the sway session. The unit shadows the distro's of the same name; GNOME still
    # starts it via /etc/xdg/autostart.
    systemd.user.services.blueman-applet = {
      Unit = {
        Description = "Bluetooth management applet";
        PartOf = [ "sway-session.target" ];
        After = [
          "sway-session.target"
          "tray.target"
        ];
      };
      Service = {
        Type = "dbus";
        BusName = "org.blueman.Applet";
        ExecStart = tools.bluemanApplet;
      };
      Install.WantedBy = [ "sway-session.target" ];
    };
  };
}
