{ pkgs, ... }: {
  # gtk.iconCache.enable = true;
  environment.systemPackages = with pkgs; [
    qemu
  ];
}
