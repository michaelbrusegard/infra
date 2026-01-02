{inputs, ...}: {
  imports = [
    inputs.nixos-raspberrypi.nixosModules.raspberry-pi-4.base
    inputs.nixos-raspberrypi.nixosModules.sd-image
  ];

  services.zigbee2mqtt.settings.serial = {
    port = "/dev/serial/by-id/usb-dresden_elektronik_ingenieurtechnik_GmbH_ConBee_II_DE2690606-if00";
    adapter = "deconz";
  };
}
