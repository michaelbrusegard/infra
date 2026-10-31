{
  lib,
  pkgs,
  ...
}: {
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals = lib.mkForce [
      pkgs.dux-files
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-hyprland
    ];
    config.common = {
      default = ["hyprland" "gtk"];
      "org.freedesktop.impl.portal.FileChooser" = ["dfiles" "gtk"];
      "org.freedesktop.impl.portal.ScreenCast" = ["hyprland"];
      "org.freedesktop.impl.portal.Screenshot" = ["hyprland"];
    };
  };
}
