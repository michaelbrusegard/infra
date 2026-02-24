{config, ...}: {
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
  home.file.".pgpass".source = config.lib.file.mkOutOfStoreSymlink config.secrets.home.pgpassFile;
}
