{
  flake.modules.homeManager.cli-extras =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      # A bare `rm file` goes to the trash; anything with flags is the real rm.
      safeRm = pkgs.writeScriptBin "rm" ''
        #!${lib.getExe pkgs.zsh}
        if [ $# -eq 1 ] && [[ "$1" != -* ]]; then
          exec ${lib.getExe' pkgs.trash-cli "trash"} "$1"
        fi
        exec ${lib.getExe' pkgs.uutils-coreutils "uutils-rm"} "$@"
      '';
    in
    {
      programs = {
        fastfetch.enable = true;
      };

      home = {
        packages =
          with pkgs;
          [
            sd
            trash-cli
            moor
            dust
            duf
            procs
            fontconfig
            ffmpeg
            imagemagick
            p7zip
            unrar
            chafa
            yt-dlp
            e2fsprogs
            safeRm
          ]
          ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
            iproute2mac
          ]
          ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
            parted
            cryptsetup
            mbpoll
            exfatprogs
          ];

        shellAliases = {
          less = "moor";
          more = "moor";
        };

        sessionVariables = {
          PAGER = "moor";
        }
        // lib.optionalAttrs (config.secrets.keys.tauriSigningPrivateKeyFile != null) {
          TAURI_SIGNING_PRIVATE_KEY = "$( [ -f ${config.secrets.keys.tauriSigningPrivateKeyFile} ] && ${lib.getExe' pkgs.uutils-coreutils "uutils-cat"} ${config.secrets.keys.tauriSigningPrivateKeyFile} )";
        };
      };
    };
}
