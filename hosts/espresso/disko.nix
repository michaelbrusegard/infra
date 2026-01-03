{
  lib,
  config,
  ...
}: let
  hasSataDrives = builtins.elem config.networking.hostName ["espresso-2" "espresso-3"];
in {
  disko.devices = {
    disk =
      {
        main = {
          type = "disk";
          device = "/dev/nvme0n1";
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
                      "/swap" = {
                        mountpoint = "/.swapvol";
                        swap.swapfile.size = "8G";
                      };
                    };
                  };
                };
              };
            };
          };
        };
      }
      // lib.optionalAttrs hasSataDrives {
        data1 = {
          type = "disk";
          device = "/dev/sda";
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
                    type = "btrfs";
                    extraArgs = ["-f"];
                    subvolumes = {
                      "/data1" = {
                        mountpoint = "/data/disk1";
                        mountOptions = ["compress=zstd" "noatime"];
                      };
                    };
                  };
                };
              };
            };
          };
        };
        data2 = {
          type = "disk";
          device = "/dev/sdb";
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
                    type = "btrfs";
                    extraArgs = ["-f"];
                    subvolumes = {
                      "/data2" = {
                        mountpoint = "/data/disk2";
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
  };
}
