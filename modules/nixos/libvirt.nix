{pkgs, ...}: {
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      ovmf.enable = true;
      swtpm.enable = true;
    };
  };

  programs.virt-manager.enable = true;

  virtualisation.spiceUSBRedirection.enable = true;

  environment.systemPackages = with pkgs; [
    qemu
    virt-viewer
  ];
}
