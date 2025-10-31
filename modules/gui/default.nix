{ config, lib, pkgs-unstable, pkgs, affinity, ... }:

let
  cfg = config.modules.gui;

  breaktimer = pkgs.appimageTools.wrapType2 {
    name = "breaktimer";
    src = pkgs.fetchurl {
      url =
        "https://github.com/tom-james-watson/breaktimer-app/releases/latest/download/BreakTimer.AppImage";
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };
  };
in {
  options.modules.gui.enable = lib.mkEnableOption "GUI applications";

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs-unstable; [
      easyeffects
      imv
      breaktimer
      burpsuite
      element-desktop
      slack
      legcord
      obsidian
      protonmail-desktop
      proton-pass
      libreoffice-fresh
      transmission_4
      inkscape-with-extensions
      gimp3-with-plugins
      scribus
      affinity.packages.x86_64-linux.v3
      blender
      freecad-wayland
      orca-slicer
      pkgs.bambu-studio
      betaflight-configurator
      qgis
      notion
      davinci-resolve
    ];
  };
}
