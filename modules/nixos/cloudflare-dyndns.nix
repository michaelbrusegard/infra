{config, ...}: {
  services.cloudflare-dyndns = {
    enable = true;
    inherit (config.secrets.cloudflare-dyndns) apiTokenFile;
    inherit (config.secrets.cloudflare-dyndns) domains;
    ipv4 = true;
    ipv6 = true;
  };

  systemd.services.cloudflare-dyndns.serviceConfig = {
    Restart = "on-failure";
    RestartSec = "30s";
  };
}
