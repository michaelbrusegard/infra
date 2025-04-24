{ pkgs, ... }: {
  gtk.iconCache.enable = true;
  environment = {
    variables = {
      RUSTICL_ENABLE = "radeonsi";
    };
    systemPackages = with pkgs; [
      fancontrol_gui
      lm_sensors
    ];
  };
}
