{
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  boot.loader.grub.devices = ["/dev/vda"];
}
