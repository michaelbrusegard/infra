{
  config,
  lib,
  ...
}: let
  hasNvidia = builtins.elem config.networking.hostName ["espresso-1" "espresso-2"];
  hasDataDisks = builtins.elem config.networking.hostName ["espresso-1" "espresso-2"];

  # espresso-1 hard-hangs under load with no printk/pstore/MCE since the 6.18
  # kernel switched the active power-management driver to amd-pstate-epp. The
  # identical-CPU sibling espresso-2 (older BIOS, different board) is stable, so
  # this is a board/VRM marginality exposed by deep C-state voltage transitions.
  # Cap idle at C1 and drop amd-pstate to avoid the transitions that wedge it.
  isFlakyBoard = config.networking.hostName == "espresso-1";
in {
  boot = {
    initrd.availableKernelModules = ["nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod"];
    kernelModules = ["kvm-amd" "nvme-tcp"];
    kernelParams =
      ["hugepagesz=2M" "hugepages=1024"]
      ++ lib.optionals isFlakyBoard ["processor.max_cstate=1" "amd_pstate=disable"];

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
