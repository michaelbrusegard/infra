{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.local.gaming;
in {
  options.local.gaming.nvidiaOffload = lib.mkOption {
    type = lib.types.bool;
    default = false;
  };

  config = {
    hardware.graphics.enable32Bit = true;
    hardware.steam-hardware.enable = true;
    boot.kernel.sysctl."vm.max_map_count" = 2147483642;

    programs = {
      steam = {
        enable = true;
        remotePlay.openFirewall = true;
        dedicatedServer.openFirewall = true;
        localNetworkGameTransfers.openFirewall = true;
        gamescopeSession.enable = true;
        extraCompatPackages = [pkgs.proton-ge-bin];
      };
      gamescope = {
        enable = true;
        capSysNice = true;
      };
      gamemode.enable = true;
    };

    # Steam launches games in their own environment, so set this once as a
    # global Launch Option in Steam: `gamemoderun mangohud prime-run %command%`.
    programs.steam.package = lib.mkIf cfg.nvidiaOffload (
      pkgs.steam.override {
        extraEnv = {
          __NV_PRIME_RENDER_OFFLOAD = "1";
          __NV_PRIME_RENDER_OFFLOAD_PROVIDER = "NVIDIA-G0";
          __GLX_VENDOR_LIBRARY_NAME = "nvidia";
          __VK_LAYER_NV_optimus = "NVIDIA_only";
        };
      }
    );
  };
}
