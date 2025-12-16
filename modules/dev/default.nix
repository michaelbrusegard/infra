{ config, lib, pkgs, system, isDarwin, fenix, pkgs-unstable, ... }:

let
  cfg = config.modules.dev;
in {
  options.modules.dev.enable = lib.mkEnableOption "Development tools configuration";

  config = lib.mkIf cfg.enable {
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
        package = pkgs-unstable.bun;
      };
      k9s.enable = true;
    };
    home = {
      packages = with pkgs; [
        sqlite
        python3
        go
        nodejs
        lua
        luarocks
        (fenix.packages.${system}.stable.withComponents [
          "rustc"
          "cargo"
          "clippy"
          "rust-src"
          "rustfmt"
        ])
      ];
      sessionVariables = {
        NODE_COMPILE_CACHE = "$HOME/.cache/nodejs-compile-cache";
      } // lib.optionalAttrs isDarwin {
        LIBRARY_PATH = "${pkgs.libiconv}/lib:$LIBRARY_PATH";
      };
    };
  };
}
