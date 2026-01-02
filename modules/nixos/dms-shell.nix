{
  pkgs,
  inputs,
  lib,
  isWsl,
  ...
}: {
  # TODO: Remove when updating to nixpkgs 26.05
  imports = [
    "${inputs.nixpkgs-unstable.${pkgs.stdenv.hostPlatform.system}.path}/nixos/modules/services/display-managers/dms-greeter.nix"
  ];

  programs.dms-shell = lib.mkIf (!isWsl) {
    enable = true;

    systemd = {
      enable = true;
      restartIfChanged = true;
    };

    enableSystemMonitoring = true;
    enableClipboard = true;
    enableVPN = true;
    enableDynamicTheming = true;
    enableAudioWavelength = true;
    enableCalendarEvents = true;
  };
}
