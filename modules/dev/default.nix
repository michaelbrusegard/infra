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
        # Misc
        podman-compose

        # Python
        uv
        python3

        # Go
        go

        # Node
        nodejs
        nodePackages.pnpm

        # Lua
        lua
        luarocks

        # C
        clang
        cmake
        lldb
      ];
      sessionVariables = {
        NODE_COMPILE_CACHE = "$HOME/.cache/nodejs-compile-cache";
      };
      activation = {
        initPodmanMachine = lib.hm.dag.entryAfter ["writeBoundary"] ''
          if ! ${pkgs.podman}/bin/podman machine inspect podman-machine-default >/dev/null 2>&1; then
            echo "Initializing default Podman machine..."
            $DRY_RUN_CMD ${pkgs.podman}/bin/podman machine init
          else
            echo "Default Podman machine already exists."
          fi
        '';
        createDockerComposeSymlink = lib.hm.dag.entryAfter ["writeBoundary"] ''
          $DRY_RUN_CMD mkdir -p $HOME/.local/bin
          $DRY_RUN_CMD ln -sf ${pkgs.podman-compose}/bin/podman-compose $HOME/.local/bin/docker-compose
        '';
      };
    };
  };
}
