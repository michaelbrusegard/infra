_: {
  # TODO(cortado): Replace this generic hardware configuration after collecting
  # `nixos-generate-config`, `lspci -nnk`, and the NIC driver information.
  boot = {
    initrd.availableKernelModules = ["nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod"];
    kernelModules = [];
  };

  hardware.enableRedistributableFirmware = true;
}
