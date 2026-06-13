_: {
  disko.devices = {
    disk = {
      disk1 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_1TB_S5GXNF0NC24072T";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              priority = 1;
              name = "ESP";
              start = "1M";
              end = "2G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["umask=0077"];
              };
            };
            swap = {
              priority = 2;
              name = "swap";
              size = "36G";
              content = {
                type = "luks";
                name = "crypted-swap";
                settings = {
                  allowDiscards = true;
                  bypassWorkqueues = true;
                };
                passwordFile = "/tmp/secret.key";
                content = {
                  type = "swap";
                  resumeDevice = true;
                };
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
              };
            };
          };
        };
      };

      disk2 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_1TB_S5GXNF0NC24057W";
        content = {
          type = "gpt";
          partitions = {
            root = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted2";
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
                    "ristretto"
                    "-d"
                    "single"
                    "-m"
                    "raid1"
                    "/dev/mapper/crypted1"
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
