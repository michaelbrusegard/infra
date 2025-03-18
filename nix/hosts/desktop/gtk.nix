{ catppuccin, ... }: {
  gtk.iconCache.enable = true;
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
};
