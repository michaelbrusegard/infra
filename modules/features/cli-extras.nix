{
  flake.modules.homeManager.cli-extras =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      programs = {
        fastfetch.enable = true;
      };

      home = {
        packages =
          with pkgs;
          [
            sd
            tealdeer
            trash-cli
            moor
            dust
            duf
            procs
            fontconfig
          ]
          ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
            iproute2mac
          ]
          ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
            parted
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
