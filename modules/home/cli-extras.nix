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
      ];

    shellAliases =
      {
        less = "moor";
        more = "moor";
        lsql = "lazysql -config $HOME/.config/lazysql/config.toml";
      }
      // lib.optionalAttrs pkgs.stdenv.isDarwin {
        groundctl = "cd $HOME/Projects/Telescope/tooling/groundctl && uv run groundctl";
      };

    sessionVariables =
      {
        PAGER = "moor";
      }
      // lib.optionalAttrs (config.secrets ? keys && config.secrets.keys ? googleGenerativeAiApiKeyFile) {
        GOOGLE_GENERATIVE_AI_API_KEY = "$( [ -f ${config.secrets.keys.googleGenerativeAiApiKeyFile} ] && ${lib.getExe' pkgs.uutils-coreutils "uutils-cat"} ${config.secrets.keys.googleGenerativeAiApiKeyFile} )";
      }
      // lib.optionalAttrs (config.secrets ? keys && config.secrets.keys ? zaiCodingApiKeyFile) {
        ZAI_CODING_API_KEY = "$( [ -f ${config.secrets.keys.zaiCodingApiKeyFile} ] && ${lib.getExe' pkgs.uutils-coreutils "uutils-cat"} ${config.secrets.keys.zaiCodingApiKeyFile} )";
      }
      // lib.optionalAttrs (config.secrets ? keys && config.secrets.keys ? anthropicApiKeyFile) {
        ANTHROPIC_API_KEY = "$( [ -f ${config.secrets.keys.anthropicApiKeyFile} ] && ${lib.getExe' pkgs.uutils-coreutils "uutils-cat"} ${config.secrets.keys.anthropicApiKeyFile} )";
      }
      // lib.optionalAttrs (config.secrets ? keys && config.secrets.keys ? openaiApiKeyFile) {
        OPENAI_API_KEY = "$( [ -f ${config.secrets.keys.openaiApiKeyFile} ] && ${lib.getExe' pkgs.uutils-coreutils "uutils-cat"} ${config.secrets.keys.openaiApiKeyFile} )";
      }
      // lib.optionalAttrs (config.secrets ? keys && config.secrets.keys ? tauriSigningPrivateKeyFile) {
        TAURI_SIGNING_PRIVATE_KEY = "$( [ -f ${config.secrets.keys.tauriSigningPrivateKeyFile} ] && ${lib.getExe' pkgs.uutils-coreutils "uutils-cat"} ${config.secrets.keys.tauriSigningPrivateKeyFile} )";
      };
  };
}
