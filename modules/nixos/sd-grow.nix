{
  lib,
  pkgs,
  ...
}: let
  lsblk = lib.getExe' pkgs.util-linux "lsblk";
  sfdisk = lib.getExe' pkgs.util-linux "sfdisk";
  partprobe = lib.getExe' pkgs.parted "partprobe";
  udevadm = lib.getExe' pkgs.systemd "udevadm";
  resize2fs = lib.getExe' pkgs.e2fsprogs "resize2fs";
in {
  # The sd-image is built to a fixed size, and sdImage.expandOnBoot is disabled
  # because its default logic grows whatever backs / - which is tmpfs here, not
  # the SD. This one-shot grows the NIXOS_SD partition (mounted as /persistent)
  # to fill the card on first boot, gated by a stamp so it runs once.
  systemd.services.grow-persistent = {
    wantedBy = ["multi-user.target"];
    after = ["local-fs.target"];
    unitConfig.ConditionPathExists = "!/persistent/.partition-expanded";
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      set -euo pipefail

      persistent_part="/dev/disk/by-label/NIXOS_SD"
      stamp="/persistent/.partition-expanded"
      boot_device="$(${lsblk} -npo PKNAME "$persistent_part")"
      part_number="$(${lsblk} -npo PARTN "$persistent_part")"

      if [ -z "$boot_device" ] || [ -z "$part_number" ]; then
        echo "Could not resolve persistent partition parent device; skipping grow."
        exit 0
      fi

      echo ",+," | ${sfdisk} -N"$part_number" --no-reread "$boot_device"
      ${partprobe} "$boot_device" || true
      ${udevadm} settle || true
      ${resize2fs} "$persistent_part"
      touch "$stamp"
    '';
  };
}
