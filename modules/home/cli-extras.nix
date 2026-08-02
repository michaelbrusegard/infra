{
  pkgs,
  lib,
  config,
  ...
}: {
  programs = {
    pay-respects = {
      enable = true;
      enableZshIntegration = true;
      options = ["--alias" "f" "--nocnf"];
    };
    fastfetch.enable = true;
  };

  home = {
    packages = with pkgs;
      [
        sd
        trash-cli
        libqalculate
        moor
        dust
        duf
        procs
        fontconfig
      ]
      ++ lib.optionals pkgs.stdenv.isDarwin [
        iproute2mac
      ]
      ++ lib.optionals pkgs.stdenv.isLinux [
        parted
      ];

    shellAliases = {
      less = "moor";
      more = "moor";
      lsql = "lazysql -config $HOME/.config/lazysql/config.toml";
    };

    sessionVariables =
      {
        PAGER = "moor";
      }
      // lib.optionalAttrs (config.secrets ? keys && config.secrets.keys ? tauriSigningPrivateKeyFile) {
        TAURI_SIGNING_PRIVATE_KEY = "$( [ -f ${config.secrets.keys.tauriSigningPrivateKeyFile} ] && ${lib.getExe' pkgs.uutils-coreutils "uutils-cat"} ${config.secrets.keys.tauriSigningPrivateKeyFile} )";
      };
  };
}
