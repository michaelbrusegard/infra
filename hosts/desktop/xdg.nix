{ pkgs, ... }: {
  xdg = {
    portal = {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
      ];
      config = {
        common = {
          default = ["hyprland" "gtk"];
        };
      };
      xdgOpenUsePortal = true;
    };
  };
}
