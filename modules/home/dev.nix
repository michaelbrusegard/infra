{
  pkgs,
  lib,
  inputs,
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

  home = {
    packages = with pkgs; [
      sqlite
      python3
      go
      nodejs
      lua
      luarocks

      (inputs.fenix.packages.${pkgs.stdenv.hostPlatform.system}.stable.withComponents [
        "rustc"
        "cargo"
        "clippy"
        "rust-src"
        "rustfmt"
      ])
    ];

    sessionVariables =
      {
        NODE_COMPILE_CACHE = "$HOME/.cache/nodejs-compile-cache";
      }
      // lib.optionalAttrs pkgs.stdenv.isDarwin {
        LIBRARY_PATH = "${pkgs.libiconv}/lib:$LIBRARY_PATH";
      };
  };
}
