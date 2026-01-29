{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  environment.systemPackages = [
    pkgs.sbctl
  ];

  boot = {
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
