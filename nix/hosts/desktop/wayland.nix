{ catppuccin, hyprland, ... }: {
  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;
    package = hyprland.packages.${system}.hyprland;
    settings = {};
  };
  catppuccin.hyprland = {
    enable = true;
    accent = "blue";
  };
};
