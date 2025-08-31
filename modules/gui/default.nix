{ config, lib, pkgs, isDarwin, ... }:

let
  cfg = config.modules.gui;
in {
  options.modules.gui.enable = lib.mkEnableOption "GUI applications";

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      transmission_4
      slack
      zoom-us
    ]
    ++ (lib.optionals (!isDarwin) [
      burpsuite
      easyeffects
      imv
      protonmail-desktop
      proton-pass
      obsidian
      element-desktop
      legcord
      davinci-resolve
      inkscape-with-extensions
      gimp3-with-plugins
      libreoffice-fresh
      orca-slicer
      freecad-wayland
      betaflight-configurator
      blender
      notion
      qgis
    ]);
  };
}
