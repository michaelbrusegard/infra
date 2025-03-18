{ system, hyprland, ... }: {
  programs = {
    hyprland = {
      enable = true;
      xwayland.enable = true;
      package = hyprland.packages.${system}.hyprland;
      portalPackage = hyprland.packages.${system}.xdg-desktop-portal-hyprland;
    };
    hyprlock.enable = true;
    yubikey-touch-detector.enable = true;
  };
};
