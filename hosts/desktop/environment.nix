{ pkgs, ... }: {
  gtk.iconCache.enable = true;
  environment = {
    variables = {
      RUSTICL_ENABLE = "radeonsi";
    };
    systemPackages = with pkgs; [
      apple-cursor
      lm_sensors
    ];
  };
}
