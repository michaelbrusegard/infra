{
  inputs,
  lib,
  ...
}:
# The path unit below gates startup on the wayland socket already existing,
# so no ExecStartPre wait is needed in the service itself.
let
  # The dms-greeter runs its own Hyprland and grabs wayland-0, so the actual
  # user session lands on wayland-1.
  uid = 1000;
  waylandSocket = "/run/user/${toString uid}/wayland-1";
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

  # The upstream unit is wantedBy default.target, so at boot it races ahead of
  # the user Wayland session, fails to connect to the compositor, and burns its
  # restart limit. Detach it from boot and start it from a path unit that fires
  # once the session's wayland socket actually exists.
  systemd.services.asus-dialpad-driver = {
    wantedBy = lib.mkForce [];
    after = ["graphical.target"];
    unitConfig.ConditionPathExists = waylandSocket;
    serviceConfig.RestartSec = lib.mkForce 5;
  };

  systemd.paths.asus-dialpad-driver = {
    description = "Start Asus DialPad Driver once the user Wayland socket exists";
    wantedBy = ["paths.target"];
    pathConfig = {
      PathExists = waylandSocket;
      Unit = "asus-dialpad-driver.service";
    };
  };
}
