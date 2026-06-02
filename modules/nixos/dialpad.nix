{
  inputs,
  lib,
  ...
}: let
  # The dms-greeter runs its own Hyprland and grabs wayland-0, so the actual
  # user session lands on wayland-1.
  uid = 1000;
  waylandSocket = "/run/user/${toString uid}/wayland-1";
in {
  imports = [
    inputs.asus-dialpad-driver.nixosModules.default
  ];

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
    serviceConfig.RestartSec = lib.mkForce 5;
  };

  systemd.paths.asus-dialpad-driver = {
    wantedBy = ["paths.target"];
    pathConfig = {
      PathExists = waylandSocket;
      Unit = "asus-dialpad-driver.service";
    };
  };
}
