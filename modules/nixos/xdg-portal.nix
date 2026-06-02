{
  lib,
  pkgs,
  ...
}: {
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals = lib.mkForce [
      pkgs.kdePackages.xdg-desktop-portal-kde
    ];
    config.common = {
      default = ["kde" "hyprland"];
      "org.freedesktop.impl.portal.FileChooser" = ["kde"];
      "org.freedesktop.impl.portal.ScreenCast" = ["hyprland"];
      "org.freedesktop.impl.portal.Screenshot" = ["hyprland"];
    };
  };
}
