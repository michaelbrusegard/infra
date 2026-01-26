{
  lib,
  isWsl,
  inputs,
  ...
}: {
  # TODO: Remove when updating to nixpkgs 26.05
  imports = [
    "${inputs.nixpkgs-unstable}/nixos/modules/programs/wayland/dms-shell.nix"
  ];

  programs.dms-shell = lib.mkIf (!isWsl) {
    enable = true;

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
