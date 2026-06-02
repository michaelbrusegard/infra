{
  inputs,
  lib,
  pkgs,
  ...
}: let
  # The dms-greeter runs its own Hyprland and grabs wayland-0, so the actual
  # user session lands on wayland-1.
  uid = 1000;
  waylandSocket = "/run/user/${toString uid}/wayland-1";
  dialpadPkg = inputs.asus-dialpad-driver.packages.${pkgs.system}.default;
  configDir = "/var/lib/asus-dialpad-driver";
in {
  imports = [
    inputs.asus-dialpad-driver.nixosModules.default
  ];

  # ProArt P16 (H7606WW) touchpad-integrated rotary dial. Enumerates via I2C,
  # not as a standalone HID, so it needs this userspace daemon to translate the
  # dial gesture into input events. Hold the touchpad's top-right corner ~1s to
  # activate the dial. asusctl handles the keyboard backlight separately.
  services.asus-dialpad-driver = {
    enable = true;
    layout = "proartp16";
    wayland = true;
    waylandDisplay = "wayland-1";
  };

  systemd.services.asus-dialpad-driver = {
    wantedBy = lib.mkForce [];
    after = ["graphical.target"];
    unitConfig.ConditionPathExists = waylandSocket;
    serviceConfig = {
      RestartSec = lib.mkForce 5;
      # The module passes the nix store path as config dir, which is read-only.
      # Override ExecStart to use a writable StateDirectory instead.
      ExecStart = lib.mkForce "${dialpadPkg}/share/asus-dialpad-driver/dialpad.py proartp16 ${configDir}/";
      StateDirectory = "asus-dialpad-driver";
      StateDirectoryMode = "0755";
    };
  };

  systemd.paths.asus-dialpad-driver = {
    wantedBy = ["paths.target"];
    pathConfig = {
      PathExists = waylandSocket;
      Unit = "asus-dialpad-driver.service";
    };
  };
}
