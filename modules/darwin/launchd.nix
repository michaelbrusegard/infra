{ ... }:

{
  launchd.user.agents = {
    ice = {
      command = "open -a Ice";
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
      command = "open -a LinearMouse";
      serviceConfig = {
        RunAtLoad = true;
        ProcessType = "Interactive";
      };
    };
    aldente = {
      command = "open -a AlDente";
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
      command = "open -a BreakTimer";
      serviceConfig = {
        RunAtLoad = true;
        ProcessType = "Interactive";
      };
    };
  };
}
