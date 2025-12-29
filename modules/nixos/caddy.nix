{ config, ... }:

{
  services.caddy = {
    enable = true;
    virtualHosts = config.secrets.caddy.virtualHosts;
  };
}
