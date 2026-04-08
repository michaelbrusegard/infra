{config, ...}: {
  services.netbird.clients.default = {
    port = 51820;
    config = {
      ManagementURL = {
        Scheme = "https";
        Host = "${config.secrets.netbird.publicDomain}:443";
      };
    };
    login = {
      enable = true;
      inherit (config.secrets.netbird) setupKeyFile;
    };
  };
}
