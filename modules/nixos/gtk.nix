{
  lib,
  isWsl,
  ...
}:
lib.mkIf (!isWsl) {
  gtk.iconCache.enable = true;
  programs.dconf.enable = true;
}
