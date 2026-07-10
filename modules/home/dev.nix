{
  pkgs,
  config,
  lib,
  homePersistenceRoot ? null,
  ...
}: {
  programs = {
    direnv = {
      enable = true;
      enableZshIntegration = true;
      silent = true;
      nix-direnv.enable = true;
    };

    bun = {
      enable = true;
      enableGitIntegration = true;
    };

    lazysql = {
      enable = true;
      settings = {
        inherit (config.secrets.lazysql.settings) database;
        application = {
          DefaultPageSize = 300;
          DisableSidebar = false;
          SidebarOverlay = false;
        };
      };
    };
  };
  home =
    {
      # file.".pgpass".source = config.lib.file.mkOutOfStoreSymlink config.secrets.home.pgpassFile;
      packages = with pkgs; [
        postgresql
        vite-plus
        deno
      ];

      file.".npmrc" = lib.mkIf (config.secrets ? keys && config.secrets.keys ? githubTokenFile) {
        text = "//npm.pkg.github.com/:_authToken=\${GH_TOKEN}\n";
      };
    }
    // lib.optionalAttrs (homePersistenceRoot != null) {
      persistence.${homePersistenceRoot}.directories = [
        ".cache/direnv"
        ".local/share/direnv"
      ];
    };
}
