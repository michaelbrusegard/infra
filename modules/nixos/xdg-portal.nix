{
  lib,
  pkgs,
  isWsl,
  ...
}: {
  xdg = lib.mkIf (!isWsl) {
    portal = {
      extraPortals = [
        pkgs.xdg-desktop-portal-gtk
      ];
      config.common.default = ["hyprland" "gtk"];
      xdgOpenUsePortal = true;
    };
  };
}
