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
}
