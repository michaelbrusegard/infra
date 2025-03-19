{ ... }: {
  boot = {
    kernelModules = [ "kvm-amd" ];
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    initrd = {
      availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
      luks.devices."luks-3326ca76-4cad-48a9-9c88-6aadd59e63fa".device = "/dev/disk/by-uuid/3326ca76-4cad-48a9-9c88-6aadd59e63fa";
    };
  };
};
