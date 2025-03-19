{ system, apple-fonts, ... }: {
  gtk = {
    enable = true;
    iconCache.enable = true;
    font = {
      name = "SF Pro";
      package = apple-fonts.packages.${system}.sf-pro;
    };
  };
  catppuccin.gtk = {
    enable = true;
    accent = "blue";
    icon = {
      enable = true;
      accent = "blue";
    };
    size = "compact";
    tweaks = [ "rimless" ];
  };
}
