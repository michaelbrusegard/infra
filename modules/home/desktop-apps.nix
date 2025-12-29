{ pkgs, inputs, ... }:

{
  home.packages = with pkgs; [
    # Audio / media
    easyeffects
    imv
    audacity
    mpv

    # Communication
    element-desktop
    slack
    legcord

    # Productivity
    obsidian
    protonmail-desktop
    proton-pass
    libreoffice-fresh
    notion

    # File / download
    transmission_4

    # Graphics / design
    inkscape-with-extensions
    gimp3-with-plugins
    scribus
    blender
    inputs.affinity.packages.x86_64-linux.v3

    # CAD / engineering
    orca-slicer
    bambu-studio
    qgis
    freecad
    betaflight-configurator
    davinci-resolve

    # Utilities
    burpsuite
    breaktimer
  ];
}
