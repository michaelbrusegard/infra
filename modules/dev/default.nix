{ config, lib, pkgs, system, isDarwin, fenix, ... }:

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
      };
    };
    home = {
      packages = with pkgs; [
        # CLI tools
        google-cloud-sdk
        gh
        act
        pkg-config

        # Database
        sqlite
        postgresql

        # Python
        uv
        python3
        gdal
        geos

        # Go
        go

        # JavaScript
        nodejs
        ni
        nodePackages.pnpm

        # Lua
        lua
        luarocks

        # Rust
        (fenix.packages.${system}.stable.withComponents [
          "rustc"
          "cargo"
          "clippy"
          "rust-src"
          "rustfmt"
        ])

        # Embedded
        arduino-cli

        # C
        cmake
        clang
        clang-tools
        lldb
        llvm
        libiconv

        # c#
        dotnet-sdk
      ] ++ lib.optionals (!isDarwin) [
        # System utilities
        systemd

        # Windows cross-compile
        nsis
      ];
      sessionVariables = {
        NODE_COMPILE_CACHE = "$HOME/.cache/nodejs-compile-cache";
      } // lib.optionalAttrs isDarwin {
        GDAL_LIBRARY_PATH = "$(gdal-config --prefix)/lib/libgdal.dylib";
        GEOS_LIBRARY_PATH = "$(geos-config --prefix)/lib/libgeos_c.dylib";
        PNPM_HOME = "$HOME/.local/state/pnpm";
        LIBRARY_PATH = "${pkgs.libiconv}/lib:$LIBRARY_PATH";
        CPATH = "${pkgs.libiconv}/include:$CPATH";
      };
    };
  };
}
