{ pkgs, ... }: {
  gtk.iconCache.enable = true;
  environment = {
    variables = {
      RUSTICL_ENABLE = "radeonsi";
    };
    systemPackages = with pkgs; [
      apple-cursor
      fancontrol_gui
      lm_sensors
    ];
  };
}
