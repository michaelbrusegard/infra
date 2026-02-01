{
  pkgs,
  inputs,
  lib,
  users,
  ...
}: {
  # TODO: Remove when updating to nixpkgs 26.05
  imports = [
    "${inputs.nixpkgs-unstable}/nixos/modules/services/display-managers/dms-greeter.nix"
  ];

  # Provide compatibility shim for services.displayManager.generic
  # which exists in nixpkgs-unstable but not in 25.11
  options.services.displayManager.generic = {
    enable =
      lib.mkEnableOption "generic display manager integration"
      // {
        default = false;
      };

    preStart = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Script executed before the display manager is started.";
    };

    execCmd = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Command to start the display manager.";
    };

    environment = lib.mkOption {
      type = with lib.types; attrsOf unspecified;
      default = {};
      description = "Additional environment variables needed by the display manager.";
    };
  };

  config = {
    environment.systemPackages = [pkgs.bibata-cursors];

    services.displayManager.dms-greeter = {
      enable = true;
      configHome = "/home/${builtins.head users}";
      compositor.name = "hyprland";
      compositor.customConfig = ''
        env = XCURSOR_THEME,Bibata-Modern-Classic
        env = XCURSOR_SIZE,24
        input {
          kb_layout = us
          kb_variant = mac
          kb_options = lv3:lalt_switch
          repeat_rate = 65
          repeat_delay = 150
          follow_mouse = 1
        }
        misc {
          disable_hyprland_logo = true
          disable_splash_rendering = true
          disable_watchdog_warning = true
        }
      '';
    };
  };
}
