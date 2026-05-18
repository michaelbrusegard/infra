{
  pkgs,
  lib,
  inputs,
  isWsl,
  ...
}: {
  home.packages = lib.mkIf (!isWsl) (with pkgs;
    [
      element-desktop
      signal-desktop
      slack
      protonmail-desktop
      inkscape-with-extensions
      audacity
      t3code
    ]
    ++ lib.optionals pkgs.stdenv.isLinux [
      imv
      legcord

      transmission_4
      proton-pass
      libreoffice-fresh
      scribus
      gimp-with-plugins
      blender
      inputs.affinity.packages.x86_64-linux.v3
      davinci-resolve
      orca-slicer
      bambu-studio
      betaflight-configurator
      qgis
      notion-app-enhanced
      wootility
      ungoogled-chromium
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [
      ice-bar
      brewCasks.raycast

      brewCasks.linearmouse
      brewCasks.legcord

      brewCasks.transmission
      brewCasks.proton-pass
      brewCasks.protonvpn
      libreoffice-bin
      brewCasks.gimp
      brewCasks.blender
      brewCasks.affinity
      brewCasks.orcaslicer
      brewCasks.bambu-studio
      brewCasks.betaflight-configurator
      brewCasks.qgis
      notion-app
      brewCasks.wootility
      utm
      brewCasks.crystalfetch
      brewCasks.ungoogled-chromium
    ]);

  xdg.mimeApps.defaultApplications = lib.mkIf (!isWsl) {
    "image/png" = ["imv.desktop"];
    "image/jpeg" = ["imv.desktop"];
  };
}
