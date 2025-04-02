{ pkgs, ... }: {
  gtk.iconCache.enable = true;
  environment.systemPackages = with pkgs; [
    qemu
    gnome-themes-extra
    adwaita-icon-theme
  ];
}
