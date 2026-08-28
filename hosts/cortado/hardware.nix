_: {
  boot = {
    initrd.availableKernelModules = ["xhci_pci" "nvme" "uas" "usbhid" "sd_mod" "sdhci_pci"];
    kernelModules = ["kvm-intel"];
  };

  hardware = {
    enableRedistributableFirmware = true;
    cpu.intel.updateMicrocode = true;
  };
}
