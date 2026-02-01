{lib, ...}: {
  config = {
    gtk.iconCache.enable = true;
    programs.dconf.enable = true;
  };

  # TODO: Remove when updating to nixpkgs 26.05
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
}
