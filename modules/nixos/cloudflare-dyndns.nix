{config, ...}: {
  services.cloudflare-dyndns = {
    enable = true;
    inherit (config.secrets.cloudflare-dyndns) apiTokenFile;
    inherit (config.secrets.cloudflare-dyndns) domains;
    ipv4 = true;
    ipv6 = false;
  };
}
