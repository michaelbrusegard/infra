{pkgs, ...}: {
  xdg = {
    portal = {
      enable = true;
      extraPortals = [
        pkgs.kdePackages.xdg-desktop-portal-kde
      ];
      config.common.default = ["hyprland" "kde"];
      xdgOpenUsePortal = true;
    };
  };
}
