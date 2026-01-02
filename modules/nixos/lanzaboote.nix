{
  pkgs,
  inputs,
  isWsl,
  lib,
  ...
}: {
  imports = [
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  environment.systemPackages = [
    pkgs.sbctl
  ];

  boot = lib.mkIf (!isWsl) {
    loader.systemd-boot.enable = false;
    loader.efi.canTouchEfiVariables = true;
    lanzaboote = {
      enable = true;
      autoGenerateKeys.enable = true;
      autoEnrollKeys = {
        enable = true;
        autoReboot = true;
      };
      pkiBundle = "/var/lib/sbctl";
    };
  };
}
