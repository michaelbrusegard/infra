{
  flake.modules.homeManager.desktop-apps =
    {
      pkgs,
      lib,
      isWsl,
      homePersistenceRoot ? null,
      ...
    }:
    let
      opencloudClient = pkgs.symlinkJoin {
        name = "${pkgs.opencloud-desktop.pname}-portal-dialogs";
        paths = [ pkgs.opencloud-desktop ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          target=$(readlink -f "$out/bin/opencloud")
          rm "$out/bin/opencloud"
          makeWrapper "$target" "$out/bin/opencloud" \
            --set QT_QPA_PLATFORMTHEME xdgdesktopportal
        '';
      };
      # The client's own "Start on login" entry points at an unwrapped store
      # path and lives in ~/.config/autostart, which impermanence wipes.
      opencloudAutostart = pkgs.makeDesktopItem {
        name = "opencloud-autostart";
        desktopName = "OpenCloud";
        exec = "${opencloudClient}/bin/opencloud";
        icon = "opencloud";
        noDisplay = true;
      };
      blenderDarwin = pkgs.brewCasks.blender.overrideAttrs (old: {
        # download.blender.org challenges non-browser fetchers with Cloudflare.
        # Keep the cask-provided hash while fetching the same artifact from a mirror.
        src = pkgs.fetchurl {
          url = "https://mirrors.ocf.berkeley.edu/blender/release/Blender${lib.versions.majorMinor old.version}/${old.src.name}";
          sha256 = old.src.outputHash;
        };
      });
    in
    {
      home = {
        packages = lib.mkIf (!isWsl) (
          with pkgs;
          [
            signal-desktop
            # Keep the desktop files while allowing slack-cli to own bin/slack.
            (lib.lowPrio slack)
            bulwark-desktop
            bitwarden-cli
            inkscape-with-extensions
            audacity
          ]
          ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
            bubbles
            mattermost-desktop
            fluffychat
            zapzap
            rustdesk-flutter
            imv
            gthumb
            legcord
            veracrypt
            feishin

            transmission_4-gtk
            bitwarden-desktop
            libreoffice-fresh
            pdfarranger
            scribus
            gimp-with-plugins
            blender
            davinci-resolve
            betaflight-configurator
            qgis
            opencloudClient
          ]
          ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
            brewCasks.raycast
            brewCasks.rustdesk
            brewCasks.mattermost
            brewCasks.whatsapp

            brewCasks.linearmouse
            brewCasks.stats
            brewCasks.legcord

            brewCasks.transmission
            brewCasks.bitwarden
            brewCasks.protonvpn
            libreoffice-bin
            brewCasks.gimp
            blenderDarwin
            brewCasks.betaflight-configurator
            brewCasks.qgis
            brewCasks.wootility
            utm
            brewCasks.crystalfetch
            brewCasks.opencloud
          ]
        );
      }
      // lib.optionalAttrs (homePersistenceRoot != null) {
        persistence = {
          ${homePersistenceRoot}.directories = [
            ".config/GIMP"
            ".config/scribus"
            ".config/inkscape"
            ".config/Signal"
            ".local/share/bubbles"
            ".config/ZapZap"
            ".local/share/ZapZap"
            ".config/Mattermost"
            ".config/Slack"
            ".config/Bulwark"
            ".config/Bitwarden"
            ".config/Bitwarden CLI"
            ".config/OpenCloud"
            ".config/legcord"
            ".config/libreoffice"
            ".config/blender"
            ".config/transmission"
            ".config/feishin"
            ".config/rustdesk"
            "Manafish"
          ];
        };
      };

      xdg.autostart = lib.mkIf (!isWsl && pkgs.stdenv.hostPlatform.isLinux) {
        enable = true;
        entries = [ "${opencloudAutostart}/share/applications/opencloud-autostart.desktop" ];
      };

      xdg.mimeApps.defaultApplications = lib.mkIf (!isWsl) {
        "image/png" = [ "imv.desktop" ];
        "image/jpeg" = [ "imv.desktop" ];
      };
    };
}
