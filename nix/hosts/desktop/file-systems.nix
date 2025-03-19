{ ... }: {
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/803ad914-684f-4789-b283-238fe939db9b";
      fsType = "ext4";
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/33B3-FDF1";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };
  };
};
