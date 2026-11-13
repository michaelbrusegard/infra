{
  config,
  lib,
  ...
}: {
  services.prometheus.exporters.smartctl = {
    enable = true;
    openFirewall = true;
    # Query only the disks disko manages. Scanning would also probe every
    # Mayastor NVMe-oF volume attached to the node.
    devices = lib.mapAttrsToList (_: disk: disk.device) config.disko.devices.disk;
  };
}
