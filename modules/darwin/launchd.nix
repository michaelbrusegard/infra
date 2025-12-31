{ pkgs, ... }:

{
  launchd.user.agents = {
    ice = {
      command = "open ${pkgs.ice-bar}/Applications/Ice.app";
      serviceConfig = {
        RunAtLoad = true;
        ProcessType = "Interactive";
      };
    };
    yabaiindicator = {
      command = "open -a YabaiIndicator";
      serviceConfig = {
        RunAtLoad = true;
        ProcessType = "Interactive";
      };
    };
    linearmouse = {
      command = "open ${pkgs.brewCasks.linearmouse}/Applications/LinearMouse.app";
      serviceConfig = {
        RunAtLoad = true;
        ProcessType = "Interactive";
      };
    };
    amphetamine = {
      command = "open -a Amphetamine";
      serviceConfig = {
        RunAtLoad = true;
        ProcessType = "Interactive";
      };
    };
    breaktimer = {
      command = "open ${pkgs.brewCasks.breaktimer}/Applications/BreakTimer.app";
      serviceConfig = {
        RunAtLoad = true;
        ProcessType = "Interactive";
      };
    };
  };
}
