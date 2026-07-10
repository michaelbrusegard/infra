{
  pkgs,
  lib,
  isWsl,
  homePersistenceRoot ? null,
  ...
}: let
  nextcloudClient = pkgs.symlinkJoin {
    name = "${pkgs.nextcloud-client.pname}-portal-dialogs";
    paths = [pkgs.nextcloud-client];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      target=$(readlink -f "$out/bin/nextcloud")
      rm "$out/bin/nextcloud"
      makeWrapper "$target" "$out/bin/nextcloud" \
        --set QT_QPA_PLATFORMTHEME xdgdesktopportal
    '';
  };
  jellyfinDesktop = pkgs.symlinkJoin {
    name = "${pkgs.jellyfin-media-player.pname}-no-chromium-gpu";
    paths = [pkgs.jellyfin-media-player];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      target=$(readlink -f "$out/bin/jellyfin-desktop")
      rm "$out/bin/jellyfin-desktop"
      makeWrapper "$target" "$out/bin/jellyfin-desktop" \
        --add-flags --disable-gpu
    '';
  };
in {
  home =
    {
      packages = lib.mkIf (!isWsl) (with pkgs;
        [
          signal-desktop
          slack
          protonmail-desktop
          inkscape-with-extensions
          audacity
          t3code
        ]
        ++ lib.optionals pkgs.stdenv.isLinux [
          fluffychat
          paseo
          paseo-desktop
          imv
          gthumb
          legcord
          jellyfinDesktop
          veracrypt
          feishin

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
          nextcloudClient
          nextcloud-talk-desktop
        ]
        ++ lib.optionals pkgs.stdenv.isDarwin [
          ice-bar
          brewCasks.raycast
          brewCasks.paseo

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
          ".config/Paseo"
          ".paseo"
          ".config/t3code"
          ".t3"
          ".config/Proton Mail"
          ".config/Proton Pass"
          ".config/Nextcloud"
          ".config/legcord"
          ".config/libreoffice"
          ".config/blender"
          ".config/jellyfin-desktop"
          ".local/share/jellyfin-desktop"
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
