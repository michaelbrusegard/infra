_: {
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
        database = [
          {
            Name = "Postgres";
            Provider = "postgres";
            URL = "postgres://\${env:DB_USER}:\${env:DB_PASSWORD}@localhost:5432/\${env:DB_NAME}";
          }
        ];
        application = {
          DefaultPageSize = 300;
          DisableSidebar = false;
          SidebarOverlay = false;
        };
      };
    };
  };
}
