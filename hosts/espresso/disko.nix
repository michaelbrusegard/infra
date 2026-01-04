{
  lib,
  config,
  ...
}: let
  diskIds = {
    "espresso-0" = {
      main = "/dev/disk/by-id/CHANGE_ME_nvme_ssd_espresso1";
    };
    "espresso-1" = {
      main = "/dev/disk/by-id/CHANGE_ME_nvme_ssd_espresso2";
      data1 = "/dev/disk/by-id/CHANGE_ME_sata_ssd1_espresso2";
      data2 = "/dev/disk/by-id/CHANGE_ME_sata_ssd2_espresso2";
    };
    "espresso-2" = {
      main = "/dev/disk/by-id/CHANGE_ME_nvme_ssd_espresso3";
      data1 = "/dev/disk/by-id/CHANGE_ME_sata_ssd1_espresso3";
      data2 = "/dev/disk/by-id/CHANGE_ME_sata_ssd2_espresso3";
    };
  };

  currentDisks = diskIds.${config.networking.hostName};
in {
  disko.devices = {
    disk =
      {
        main = {
          type = "disk";
          device = currentDisks.main;
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                priority = 1;
                name = "ESP";
                start = "1M";
                end = "512M";
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
                  name = "crypted";
                  settings = {
                    allowDiscards = true;
                    bypassWorkqueues = true;
                  };
                  passwordFile = "/tmp/secret.key";
                  content = {
                    type = "btrfs";
                    extraArgs = ["-f"];
                    subvolumes = {
                      "/root" = {
                        mountpoint = "/";
                        mountOptions = ["compress=zstd" "noatime"];
                      };
                      "/home" = {
                        mountpoint = "/home";
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
      }
      // lib.optionalAttrs (builtins.hasAttr "data1" currentDisks) {
        data1 = {
          type = "disk";
          device = currentDisks.data1;
          content = {
            type = "gpt";
            partitions = {
              root = {
                size = "100%";
                content = {
                  type = "luks";
                  name = "crypted-data1";
                  settings = {
                    allowDiscards = true;
                    bypassWorkqueues = true;
                  };
                  passwordFile = "/tmp/secret.key";
                  content = {
                    type = "filesystem";
                    format = "ext4";
                    mountpoint = "/data/disk1";
                    mountOptions = ["noatime"];
                  };
                };
              };
            };
          };
        };
        data2 = {
          type = "disk";
          device = currentDisks.data2;
          content = {
            type = "gpt";
            partitions = {
              root = {
                size = "100%";
                content = {
                  type = "luks";
                  name = "crypted-data2";
                  settings = {
                    allowDiscards = true;
                    bypassWorkqueues = true;
                  };
                  passwordFile = "/tmp/secret.key";
                  content = {
                    type = "filesystem";
                    format = "ext4";
                    mountpoint = "/data/disk2";
                    mountOptions = ["noatime"];
                  };
                };
              };
            };
          };
        };
      };
  };
}
