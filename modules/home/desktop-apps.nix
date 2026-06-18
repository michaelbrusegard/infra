{
  pkgs,
  lib,
  isWsl,
  homePersistenceRoot ? null,
  ...
}: {
  home =
    {
      packages = lib.mkIf (!isWsl) (with pkgs;
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
          gthumb
          legcord
          jellyfin-media-player

          transmission_4-gtk
          proton-pass
          libreoffice-fresh
          pdfarranger
          scribus
          gimp-with-plugins
          blender
          davinci-resolve
          betaflight-configurator
          qgis
          ungoogled-chromium
          nextcloud-client
          nextcloud-talk-desktop
          supersonic-wayland
        ]
        ++ lib.optionals pkgs.stdenv.isDarwin [
          ice-bar
          brewCasks.raycast

          brewCasks.linearmouse
          brewCasks.legcord
          brewCasks.jellyfin-media-player

          brewCasks.transmission
          brewCasks.proton-pass
          brewCasks.protonvpn
          libreoffice-bin
          brewCasks.gimp
          brewCasks.blender
          brewCasks.betaflight-configurator
          brewCasks.qgis
          brewCasks.wootility
          utm
          brewCasks.crystalfetch
          brewCasks.ungoogled-chromium
          brewCasks.nextcloud
          brewCasks.nextcloud-talk
          supersonic
        ]);
    }
    // lib.optionalAttrs (homePersistenceRoot != null) {
      persistence = {
        ${homePersistenceRoot}.directories = [
          ".config/GIMP"
          ".config/scribus"
          ".config/inkscape"
          ".config/Signal"
          ".config/Slack"
          ".config/Proton Mail"
          ".config/Proton Pass"
          ".config/legcord"
          ".config/libreoffice"
          ".config/blender"
          ".local/share/Jellyfin Media Player"
          ".config/transmission"
          ".config/supersonic"
        ];
      };
    };

  xdg.mimeApps.defaultApplications = lib.mkIf (!isWsl) {
    "image/png" = ["imv.desktop"];
    "image/jpeg" = ["imv.desktop"];
  };
}
