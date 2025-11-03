{ config, lib, pkgs-unstable, pkgs, affinity, ... }:

let
  cfg = config.modules.gui;

  breaktimer = pkgs.appimageTools.wrapType2 {
    pname = "breaktimer";
    version = "2.0.1";
     src = pkgs.fetchurl {
       url = "https://github.com/tom-james-watson/breaktimer-app/releases/download/v2.0.1/BreakTimer.AppImage";
       hash = "sha256-FTOy3oBzQTyKTdxihS5Ua1VB4YlxrQMk6kenNp4hTzY=";
     };
  };
in {
  options.modules.gui.enable = lib.mkEnableOption "GUI applications";

  config = lib.mkIf cfg.enable {
    xdg.desktopEntries.breaktimer = {
      name = "BreakTimer";
      exec = "breaktimer %U";
      type = "Application";
      categories = [ "Utility" ];
    };
    home.packages = with pkgs-unstable; [
      easyeffects
      breaktimer
      imv
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
    catppuccin = {
      element-desktop.enable = true;
      imv.enable = true;
    };
  };
}
