{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.dms.nixosModules.default
  ];

  programs.dank-material-shell = {
    enable = true;
    package = pkgs.dms-shell;

    systemd = {
      enable = true;
      restartIfChanged = true;
    };

    enableSystemMonitoring = true;
    enableVPN = true;
    enableAudioWavelength = true;
    enableCalendarEvents = true;
  };
}
