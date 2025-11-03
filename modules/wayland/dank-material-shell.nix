{ config, lib, ... }:

let
  cfg = config.modules.wayland;
in {
  config = lib.mkIf cfg.enable {
    programs = {
      quickshell = {
        enable = true;
        systemd.enable = true;
      };
      dankMaterialShell = {
        enable = true;
        enableSystemd = true;
        enableSystemMonitoring = true;
        enableClipboard = true;
        enableVPN = true;
        enableBrightnessControl = true;
        enableColorPicker = true;
        enableDynamicTheming = true;
        enableAudioWavelength = true;
        enableCalendarEvents = true;
        enableSystemSound = true;
      };
    };
  };
}
