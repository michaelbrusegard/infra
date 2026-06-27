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
          signal-desktop
          slack
          protonmail-desktop
          inkscape-with-extensions
          audacity
          feishin
          t3code
        ]
        ++ lib.optionals pkgs.stdenv.isLinux [
          fluffychat
          imv
          gthumb
          legcord
          jellyfin-media-player
          veracrypt

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
        ]
        ++ lib.optionals pkgs.stdenv.isDarwin [
          ice-bar
          brewCasks.raycast

          brewCasks.linearmouse
          brewCasks.legcord
          brewCasks.jellyfin-media-player
          brewCasks.veracrypt

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
        ]);
    }
    // lib.optionalAttrs (pkgs.stdenv.isLinux && !isWsl) {
      activation.enableNextcloudExperimentalOptions = lib.hm.dag.entryAfter ["writeBoundary"] ''
        nextcloudCfg="$HOME/.config/Nextcloud/nextcloud.cfg"
        $DRY_RUN_CMD mkdir -p "$HOME/.config/Nextcloud"

        if [ -f "$nextcloudCfg" ]; then
          if grep -q '^showExperimentalOptions=' "$nextcloudCfg"; then
            $DRY_RUN_CMD sed -i 's/^showExperimentalOptions=.*/showExperimentalOptions=true/' "$nextcloudCfg"
          elif grep -q '^\[General\]$' "$nextcloudCfg"; then
            $DRY_RUN_CMD sed -i '/^\[General\]$/a showExperimentalOptions=true' "$nextcloudCfg"
          else
            $DRY_RUN_CMD printf '\n[General]\nshowExperimentalOptions=true\n' >> "$nextcloudCfg"
          fi
        else
          $DRY_RUN_CMD printf '[General]\nshowExperimentalOptions=true\n' > "$nextcloudCfg"
        fi
      '';
    }
    // lib.optionalAttrs (homePersistenceRoot != null) {
      persistence = {
        ${homePersistenceRoot}.directories = [
          ".config/GIMP"
          ".config/scribus"
          ".config/inkscape"
          ".config/Signal"
          ".config/Slack"
          ".config/t3code"
          ".t3"
          ".config/Proton Mail"
          ".config/Proton Pass"
          ".config/Nextcloud"
          ".config/legcord"
          ".config/libreoffice"
          ".config/blender"
          ".local/share/Jellyfin Media Player"
          ".config/transmission"
          ".config/feishin"
          "Manafish"
        ];
      };
    };

  xdg.mimeApps.defaultApplications = lib.mkIf (!isWsl) {
    "image/png" = ["imv.desktop"];
    "image/jpeg" = ["imv.desktop"];
  };
}
