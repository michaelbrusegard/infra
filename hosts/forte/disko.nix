_: {
  disko.devices = {
    disk = {
      disk1 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-MTFDKBA2T0QGN-1BN1AABGA_25194FF55405";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              priority = 1;
              name = "ESP";
              start = "1M";
              end = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["umask=0077"];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted1";
                settings = {
                  allowDiscards = true;
                  bypassWorkqueues = true;
                };
                passwordFile = "/tmp/secret.key";
                content = {
                  type = "btrfs";
                  extraArgs = [
                    "-f"
                    "-L"
                    "forte"
                  ];
                  subvolumes = {
                    "/persistent" = {
                      mountpoint = "/persistent";
                      mountOptions = ["compress=zstd" "noatime"];
                    };
                    "/nix" = {
                      mountpoint = "/nix";
                      mountOptions = ["compress=zstd" "noatime"];
                    };
                  };
                };
              };
            };
          };
        };
      };
    };

    nodev = {
      "/" = {
        fsType = "tmpfs";
        mountOptions = ["defaults" "mode=755"];
      };
    };
  };

  fileSystems = {
    "/persistent".neededForBoot = true;
    "/nix".neededForBoot = true;
  };
}
