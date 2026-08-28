_: {
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-TWSC_TSC3AN128-H2T70S_TTSFA258HX00212";
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
                type = "filesystem";
                format = "ext4";
                mountpoint = "/persistent";
                mountOptions = ["noatime"];
                postMountHook = ''
                  persistent="$(findmnt -n -o TARGET --source "$device")"
                  mkdir -p "$persistent/nix"
                  rootMnt="$(dirname "$persistent")"
                  mkdir -p "$rootMnt/nix"
                  mount --bind "$persistent/nix" "$rootMnt/nix"
                '';
              };
            };
          };
        };
      };
    };

    nodev."/" = {
      fsType = "tmpfs";
      mountOptions = ["defaults" "mode=755"];
    };
  };

  fileSystems = {
    "/persistent".neededForBoot = true;

    "/nix" = {
      neededForBoot = true;
      depends = ["/persistent"];
      device = "/persistent/nix";
      fsType = "none";
      options = ["bind"];
    };
  };
}
