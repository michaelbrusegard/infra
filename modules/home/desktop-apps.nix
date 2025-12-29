{ pkgs, lib, inputs, isWsl, ... }:

{
  home.packages = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) (with pkgs; [
    breaktimer
    mpv
    imv
    burpsuite
    element-desktop
    slack
    legcord
    obsidian
    proton-pass
    protonmail-desktop
    libreoffice-fresh
    transmission_4
    inkscape-with-extensions
    gimp3-with-plugins
    scribus
    inputs.affinity.packages.x86_64-linux.v3
    davinci-resolve
    blender
    freecad
    orca-slicer
    bambu-studio
    betaflight-configurator
    qgis
    notion
    audacity
  ]);
}
