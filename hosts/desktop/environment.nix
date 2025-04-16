{ pkgs, ... }: {
  gtk.iconCache.enable = true;
  environment.systemPackages = with pkgs; [
    qemu
    fancontrol_gui
    lm_sensors
  ];
}
