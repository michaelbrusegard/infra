{
  flake.modules.nixos.gtk = {
    gtk.iconCache.enable = true;
    programs.dconf.enable = true;
  };
}
