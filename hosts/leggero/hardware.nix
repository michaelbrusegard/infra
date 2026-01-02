{inputs, ...}: {
  imports = [
    inputs.nixos-raspberrypi.nixosModules.raspberry-pi-4.base
    inputs.nixos-raspberrypi.nixosModules.sd-image
  ];

  services.openthread-border-router.radio = {
    device = "/dev/serial/by-id/usb-dresden_elektronik_Thread_RCP__ConBee_II__DE2688235-if00";
    flowControl = true;
  };
}
