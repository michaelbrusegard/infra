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
}
