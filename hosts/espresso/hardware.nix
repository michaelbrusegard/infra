{
  config,
  lib,
  ...
}: let
  hasNvidia = builtins.elem config.networking.hostName ["espresso-2" "espresso-3"];
in {
  boot.initrd.availableKernelModules = ["nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod"];
  boot.kernelModules = ["kvm-amd"];

  hardware = {
    enableRedistributableFirmware = true;
    cpu.amd.updateMicrocode = true;

    graphics = {
      enable = true;
      enable32Bit = true;
    };
    nvidia = lib.mkIf hasNvidia {
      modesetting.enable = true;
      powerManagement.enable = false;
    };
  };

  services.xserver.videoDrivers = lib.mkIf hasNvidia ["nvidia"];
}
