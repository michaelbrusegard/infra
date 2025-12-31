{config, ...}: {
  services.cloudflare-dyndns = {
    enable = true;
    apiTokenFile = config.secrets.cloudflare-dyndns.apiTokenFile;
    domains = config.secrets.cloudflare-dyndns.domains;
    ipv4 = true;
    ipv6 = false;
  };
}
