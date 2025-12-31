{config, ...}: {
  services.grafana = {
    enable = true;

    settings = {
      server.http_addr = "0.0.0.0";

      security = {
        admin_user = "admin";
        admin_password = config.sops.secrets.grafana.settings.security.adminPasswordFile;
      };

      users.default_language = "en-GB";
    };

    provision.enable = true;

    provision.datasources.settings.datasources = [
      {
        name = "Prometheus";
        type = "prometheus";
        access = "proxy";
        url = "http://127.0.0.1:9090";
        isDefault = true;
      }
    ];
  };
}
