{ config, lib, pkgs, isDarwin, ... }:

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
        # Database
        libpq

        # LLM CLIS
        opencode
        gemini-cli

        # Python
        uv
        python3
        gdal
        geos

        # Go
        go

        # Node
        nodejs
        nodePackages.pnpm

        # Lua
        lua
        luarocks

        # Rust
        rustup

        # Embedded
        arduino-cli

        # C
        cmake
        lldb
        llvmPackages.llvm
        llvmPackages.lld
      ] ++ lib.optionals (!isDarwin) [
        # Windows cross-compile
        nsis
      ];
      sessionVariables = {
        NODE_COMPILE_CACHE = "$HOME/.cache/nodejs-compile-cache";
      } // lib.optionalAttrs isDarwin {
        GDAL_LIBRARY_PATH = "$(gdal-config --prefix)/lib/libgdal.dylib";
        GEOS_LIBRARY_PATH = "$(geos-config --prefix)/lib/libgeos_c.dylib";
        PNPM_HOME = "$HOME/.local/state/pnpm";
      };
    };
  };
}
