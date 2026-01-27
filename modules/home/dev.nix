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
