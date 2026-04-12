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
    kernelModules = ["kvm-amd" "nvme-tcp"];
    kernelParams = ["hugepagesz=2M" "hugepages=1024"];

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
    nvidia-container-toolkit.enable = lib.mkIf hasNvidia true;
  };

  services.xserver.videoDrivers = lib.mkIf hasNvidia ["nvidia"];

  # Configure k3s's bundled containerd to use the nvidia runtime on GPU nodes.
  # hardware.nvidia-container-toolkit generates CDI specs but does NOT configure
  # k3s's internal containerd — this template does.
  services.k3s.containerdConfigTemplate = lib.mkIf hasNvidia ''
    {{ template "base" . }}

    [plugins."io.containerd.grpc.v1.cri".containerd]
      default_runtime_name = "nvidia"

    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
      runtime_type = "io.containerd.runc.v2"

    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
      BinaryName = "${lib.getOutput "tools" config.hardware.nvidia-container-toolkit.package}/bin/nvidia-container-runtime"
      SystemdCgroup = true
  '';
}
