{config, ...}: {
  services.caddy = {
    enable = true;
    inherit (config.secrets.caddy) virtualHosts;
  };
}
