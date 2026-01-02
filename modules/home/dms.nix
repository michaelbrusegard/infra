{
  pkgs,
  lib,
  config,
  isWsl,
  inputs,
  ...
}: let
  dmsConfig = inputs.self + "/config/dms";
in {
  home.packages = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) (with pkgs; [
    polkit_gnome
    grim
    slurp
    wf-recorder
  ]);

  home.sessionVariables = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
    QT_QPA_PLATFORM = "wayland";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    QT_QPA_PLATFORMTHEME = "gtk3";
    QT_QPA_PLATFORMTHEME_QT6 = "gtk3";
  };

  xdg.configFile."DankMaterialShell".source =
    lib.mkIf (pkgs.stdenv.isLinux && !isWsl)
    config.lib.file.mkOutOfStoreSymlink
    dmsConfig;
}
