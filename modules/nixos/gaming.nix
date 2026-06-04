{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.local.gaming;

  # Toggle Hyprland's touchpad disable-while-typing so it doesn't suppress the
  # touchpad while holding movement keys during a game. Runs in the user
  # session GameMode is started from; harmless on hosts without a touchpad.
  hyprctl = "${pkgs.hyprland}/bin/hyprctl";
  dwtToggle = state: "${hyprctl} keyword input:touchpad:disable_while_typing ${state} || true";
in {
  options.local.gaming = {
    nvidiaOffload = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    touchpadDwtToggle = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
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
      gamemode = {
        enable = true;
        settings = lib.mkIf cfg.touchpadDwtToggle {
          custom = {
            start = dwtToggle "false";
            end = dwtToggle "true";
          };
        };
      };
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
