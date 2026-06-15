{
  inputs,
  lib,
  pkgs,
  config,
  ...
}: {
  imports = [
    inputs.nixos-raspberrypi.nixosModules.raspberry-pi-4.base
    inputs.nixos-raspberrypi.nixosModules.sd-image
  ];

  # Vendor RPi kernel's zfs build mismatches the zfs userspace; manata is ext4.
  boot.supportedFilesystems.zfs = lib.mkForce false;

  # nixos-raspberrypi's u-boot + root=fstab needs the classic initrd; systemd
  # initrd (on by the shared boot module) hangs early here.
  boot.initrd.systemd.enable = lib.mkForce false;

  # In PATH so systemd finds mount.fuse.mergerfs.
  environment.systemPackages = [pkgs.mergerfs];

  # LUKS data drives, unlocked post-boot from the sops keyfile (no TPM on Pi).
  # headless=yes never prompts; nofail lets boot proceed if a drive is absent.
  environment.etc.crypttab.text = ''
    manata-d1 LABEL=manata-d1-crypt ${config.secrets.luks.keyFile} nofail,headless=yes
    manata-d2 LABEL=manata-d2-crypt ${config.secrets.luks.keyFile} nofail,headless=yes
  '';

  fileSystems = {
    # Impermanence: tmpfs root, state on the SD /persistent partition.
    "/" = lib.mkForce {
      device = "none";
      fsType = "tmpfs";
      options = ["defaults" "mode=755"];
    };

    "/persistent" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
      options = ["noatime"];
      neededForBoot = true;
    };

    "/nix" = {
      device = "/persistent/nix";
      fsType = "none";
      options = ["bind"];
      neededForBoot = true;
      depends = ["/persistent"];
    };

    "/boot" = {
      device = "/persistent/boot";
      fsType = "none";
      options = ["bind"];
      neededForBoot = true;
      depends = ["/persistent"];
    };

    "/mnt/disk1" = {
      device = "/dev/mapper/manata-d1";
      fsType = "ext4";
      options = ["noatime" "nofail"];
    };

    "/mnt/disk2" = {
      device = "/dev/mapper/manata-d2";
      fsType = "ext4";
      options = ["noatime" "nofail"];
    };

    # mergerfs union, no RAID. category.create=ff fills disk1 before disk2;
    # add a drive via another /mnt/diskN branch + requires-mounts-for.
    "/srv/backup" = {
      device = "/mnt/disk1:/mnt/disk2";
      fsType = "fuse.mergerfs";
      options = [
        "defaults"
        "allow_other"
        "use_ino"
        "cache.files=partial"
        "dropcacheonclose=true"
        "category.create=ff"
        "moveonenospc=true"
        "minfreespace=4G"
        "fsname=manata-pool"
        "nofail"
        "x-systemd.requires-mounts-for=/mnt/disk1"
        "x-systemd.requires-mounts-for=/mnt/disk2"
      ];
    };
  };

  sdImage.nixPathRegistrationFile = "/persistent/nix-path-registration";
  # expand-on-boot walks `findmnt / ` which is tmpfs here; SD is sized at flash.
  sdImage.expandOnBoot = false;
}
