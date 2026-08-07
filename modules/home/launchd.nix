{
  pkgs,
  lib,
  ...
}:
lib.mkIf pkgs.stdenv.isDarwin {
  launchd.agents = {
    ice = {
      enable = true;
      config = {
        ProgramArguments = [
          "/usr/bin/open"
          "${pkgs.ice-bar}/Applications/Ice.app"
        ];
        RunAtLoad = true;
        LimitLoadToSessionType = "Aqua";
      };
    };

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

    amphetamine = {
      enable = true;
      config = {
        ProgramArguments = [
          "/usr/bin/open"
          "-a"
          "Amphetamine"
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

    handy = {
      enable = true;
      config = {
        ProgramArguments = [
          "/Applications/Handy.app/Contents/MacOS/Handy"
          "--start-hidden"
        ];
        RunAtLoad = true;
        LimitLoadToSessionType = "Aqua";
      };
    };
  };
}
