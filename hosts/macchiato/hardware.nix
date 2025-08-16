{ nixos-raspberrypi, ... }: {
  imports = [
    nixos-raspberrypi.nixosModules.raspberry-pi-4.base
    nixos-raspberrypi.nixosModules.sd-image
  ];
  hardware.bluetooth.enable = true;
}
