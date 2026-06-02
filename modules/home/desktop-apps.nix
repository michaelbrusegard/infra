{
  pkgs,
  lib,
  isWsl,
  homePersistenceRoot ? null,
  ...
}:
{
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
      davinci-resolve
      orca-slicer
      bambu-studio
      betaflight-configurator
      qgis
      wootility
      ungoogled-chromium
      nextcloud-client
      nextcloud-talk-desktop
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
      brewCasks.orcaslicer
      brewCasks.bambu-studio
      brewCasks.betaflight-configurator
      brewCasks.qgis
      brewCasks.wootility
      utm
      brewCasks.crystalfetch
      brewCasks.ungoogled-chromium
      brewCasks.nextcloud
      brewCasks.nextcloud-talk
    ]);

  xdg.mimeApps.defaultApplications = lib.mkIf (!isWsl) {
    "image/png" = ["imv.desktop"];
    "image/jpeg" = ["imv.desktop"];
  };
}
// lib.optionalAttrs (homePersistenceRoot != null) {
  home.persistence.${homePersistenceRoot}.directories = [
    ".config/OrcaSlicer"
    ".config/GIMP"
    ".config/scribus"
    ".config/inkscape"
    ".config/Signal"
    ".config/Proton Mail"
    ".config/Proton Pass"
    ".config/libreoffice"
  ];
}
