{ system, hyprland, catppuccin, ... }: {
  programs = {
    hyprland = {
      enable = true;
      xwayland.enable = true;
      package = hyprland.packages.${system}.hyprland;
      portalPackage = hyprland.packages.${system}.xdg-desktop-portal-hyprland;
    };
    catppuccin.hyprland = {
      enable = true;
      accent = "blue";
    };
    hyprlock = {
      enable = true;
    };
    catppuccin.hyprlock = {
      enable = true;
      accent = "blue";
    };
    waybar = {
      enable = true;
    };
    catppuccin.waybar = {
      enable = true;
      mode = "prependImport";
    };
    rofi = {
      enable = true;
    };
    catppuccin.rofi.enable = true;
    yubikey-touch-detector.enable = true;
  };
};
