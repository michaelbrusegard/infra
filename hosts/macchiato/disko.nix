_: {
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/sda";
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
              type = "filesystem";
              format = "ext4";
              mountpoint = "/persistent";
              mountOptions = ["noatime"];
              postMountHook = ''
                mkdir -p "$(findmnt -n -o TARGET --source "$device")/nix"
              '';
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

      "/nix" = {
        fsType = "none";
        device = "/persistent/nix";
        mountOptions = ["bind"];
      };
    };
  };

  fileSystems = {
    "/persistent".neededForBoot = true;

    "/nix" = {
      neededForBoot = true;
      depends = ["/persistent"];
    };
  };
}
