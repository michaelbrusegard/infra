{config, ...}: {
  boot = {
    initrd.availableKernelModules = [
      "nvme"
      "xhci_pci"
      "usbhid"
      "usb_storage"
      "sd_mod"
    ];
    kernelModules = ["kvm-amd"];

    kernelParams = [
      "quiet"
      "nvidia-drm.modeset=1"
    ];
    consoleLogLevel = 3;

    initrd.luks.devices = {
      crypted1.crypttabExtraOpts = ["tpm2-device=auto"];
    };
  };

  hardware = {
    enableRedistributableFirmware = true;
    cpu.amd.updateMicrocode = true;
    bluetooth.enable = true;

    graphics = {
      enable = true;
      enable32Bit = true;
    };

    nvidia = {
      modesetting.enable = true;
      open = true;
      nvidiaSettings = true;
      powerManagement.enable = true;
      package = config.boot.kernelPackages.nvidiaPackages.beta;

      # PRIME render offload (AMD iGPU primary, dGPU on-demand via
      # `nvidia-offload <cmd>`).
      #
      # Bus IDs depend on the running kernel's enumeration and aren't
      # known until first boot. Two-step bootstrap:
      #   1. Leave this block commented for the install; system boots
      #      fine with the dGPU idle-ish.
      #   2. After first login:
      #        lspci -nn | grep -E 'VGA|3D|Display'
      #      Convert hex bus:device.func to decimal PCI:B:D:F.
      #      e.g. `05:00.0` → "PCI:5:0:0", `01:00.0` → "PCI:1:0:0".
      #   3. Uncomment, set the IDs, rebuild.
      #
      # prime = {
      #   offload = {
      #     enable = true;
      #     enableOffloadCmd = true;
      #   };
      #   amdgpuBusId = "PCI:?:0:0";
      #   nvidiaBusId = "PCI:?:0:0";
      # };
    };
  };

  services = {
    xserver.videoDrivers = ["nvidia"];
    asusd = {
      enable = true;
      enableUserService = true;
    };

    power-profiles-daemon.enable = true;
    fwupd.enable = true;
  };
  local.hyprland.monitors = [
    "eDP-1,3840x2400@120,0x0,2,cm,wide,bitdepth,10"
    ",preferred,auto,1"
  ];

  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  # `lspci` for the one-time PRIME bus-ID step. Diagnostic tools come
  # from other modules / nix-shell when needed.
  environment.systemPackages = [pkgs.pciutils];
}
