{
  config,
  lib,
  ...
}: let
  hasNvidia = builtins.elem config.networking.hostName ["espresso-1" "espresso-2"];
  hasDataDisks = builtins.elem config.networking.hostName ["espresso-1" "espresso-2"];
in {
  boot = {
    initrd.availableKernelModules = ["nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod"];
    kernelModules = ["kvm-amd"];

    initrd.luks.devices =
      {
        crypted.crypttabExtraOpts = ["tpm2-device=auto"];
      }
      // lib.optionalAttrs hasDataDisks {
        crypted-data1.crypttabExtraOpts = ["tpm2-device=auto"];
        crypted-data2.crypttabExtraOpts = ["tpm2-device=auto"];
      };
  };

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
      open = false;
    };
  };

  services.xserver.videoDrivers = lib.mkIf hasNvidia ["nvidia"];
}
