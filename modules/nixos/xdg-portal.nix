{pkgs, ...}: {
  xdg = {
    portal = {
      enable = true;
      extraPortals = [
        pkgs.xdg-desktop-portal-kde
      ];
      config.common.default = ["hyprland" "kde"];
      xdgOpenUsePortal = true;
    };
  };
}
