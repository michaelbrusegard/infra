{
  pkgs,
  lib,
  config,
  isWsl,
  ...
}: let
  dmsConfig = "${config.home.homeDirectory}/Projects/nix-config/config/dms";
in {
  home = {
    sessionVariables = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
      QT_QPA_PLATFORM = "wayland";
      ELECTRON_OZONE_PLATFORM_HINT = "auto";
      QT_QPA_PLATFORMTHEME = "gtk3";
      QT_QPA_PLATFORMTHEME_QT6 = "gtk3";
    };

    pointerCursor = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
      package = pkgs.apple-cursor;
      name = "macOS";
      size = 24;
      gtk.enable = true;
      x11.enable = true;
    };
  };

  xdg.configFile = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
    "DankMaterialShell".source = config.lib.file.mkOutOfStoreSymlink dmsConfig;
  };
}
