{pkgs, ...}: {
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

    yabaiindicator = {
      enable = true;
      config = {
        ProgramArguments = [
          "/usr/bin/open"
          "-a"
          "YabaiIndicator"
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

    breaktimer = {
      enable = true;
      config = {
        ProgramArguments = [
          "/usr/bin/open"
          "${pkgs.brewCasks.breaktimer}/Applications/BreakTimer.app"
        ];
        RunAtLoad = true;
        LimitLoadToSessionType = "Aqua";
      };
    };
  };
}
