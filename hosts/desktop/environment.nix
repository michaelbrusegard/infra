{ pkgs, ... }: {
  gtk.iconCache.enable = true;
  gtk.enable = true;
  environment.systemPackages = with pkgs; [
    qemu
  ];
}
