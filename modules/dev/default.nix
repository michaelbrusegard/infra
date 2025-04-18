{ config, lib, pkgs, ... }:

let
  cfg = config.modules.dev;
in {
  options.modules.dev.enable = lib.mkEnableOption "Development tools configuration";

  config = lib.mkIf cfg.enable {
    programs = {
      direnv = {
        enable = true;
        enableZshIntegration = true;
        nix-direnv.enable = true;
      };
      bun = {
        enable = true;
        enableGitIntegration = true;
      };
    };
    services.podman = {
      enable = true;
    };
    home = {
      packages = with pkgs; [
        # Misc
        podman-compose

        # Python
        uv
        python3

        # Rust
        rustup

        # Go
        go

        # Node
        nodejs
        nodePackages.pnpm

        # Java
        jdk
        maven

        # Kotlin
        gradle

        # C
        clang
        cmake
        lldb

        # Lua
        lua
        luarocks

        # CLI
        supabase-cli
      ];
      activation = {
        createDockerComposeSymlink = lib.hm.dag.entryAfter ["writeBoundary"] ''
          $DRY_RUN_CMD mkdir -p $HOME/.local/bin
          $DRY_RUN_CMD ln -sf ${pkgs.podman-compose}/bin/podman-compose $HOME/.local/bin/docker-compose
          $DRY_RUN_CMD ln -sf ${pkgs.podman}/bin/podman $HOME/.local/bin/docker
        '';
      };
    };
  };
}
