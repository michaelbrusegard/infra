{ pkgs, ... }: {
  xdg = {
    autostart.enable = true;
    icons.enable = true;
    mime.enable = true;
    portal = {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
        xdg-desktop-portal-hyprland
      ];
    };
    sounds.enable = true;
    mimeApps.enable = true;
  };
};
