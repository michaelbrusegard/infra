{
  pkgs,
  lib,
  ...
}:
lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
  launchd.agents = {
    raycast = {
      enable = true;
      config = {
        ProgramArguments = [
          "/usr/bin/open"
          "${pkgs.brewCasks.raycast}/Applications/Raycast.app"
        ];
        RunAtLoad = true;
        LimitLoadToSessionType = "Aqua";
      };
    };

    rustdesk = {
      enable = true;
      config = {
        ProgramArguments = [
          "/usr/bin/open"
          "${pkgs.brewCasks.rustdesk}/Applications/RustDesk.app"
        ];
        RunAtLoad = true;
        LimitLoadToSessionType = "Aqua";
      };
    };

    linearmouse = {
      enable = true;
      config = {
        ProgramArguments = [
          "/usr/bin/open"
          "${pkgs.brewCasks.linearmouse}/Applications/LinearMouse.app"
        ];
        RunAtLoad = true;
        LimitLoadToSessionType = "Aqua";
      };
    };

    netbird-ui = {
      enable = true;
      config = {
        ProgramArguments = [
          "/usr/bin/open"
          "-a"
          "Netbird UI"
        ];
        RunAtLoad = true;
        LimitLoadToSessionType = "Aqua";
      };
    };
  };
}
