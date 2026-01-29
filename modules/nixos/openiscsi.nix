{
  pkgs,
  config,
  ...
}: {
  services.openiscsi = {
    enable = true;
    enableAutoLoginOut = true;
    name = "iqn.2026-01.local.k3s:${config.networking.hostName}";
  };

  environment.systemPackages = with pkgs; [
    openiscsi
  ];

  # Longhorn (via nsenter) expects host binaries like iscsiadm to be visible
  # inside the iscsid mount namespace. On NixOS this is not true by default,
  # so we bind the system profile bin path to ensure stable iSCSI operation.
  systemd.services.iscsid.serviceConfig = {
    PrivateMounts = "yes";
    BindPaths = "/run/current-system/sw/bin:/bin";
  };

  # Make iscsiadm and mount visible on a standard linux path
  systemd.tmpfiles.rules = [
    "L+ /usr/bin/iscsiadm - - - - /run/current-system/sw/bin/iscsiadm"
    "L+ /usr/bin/mount    - - - - /run/current-system/sw/bin/mount"
  ];
}
