{pkgs, ...}: {
  services.grafana.provision.dashboards.settings.providers = [
    {
      name = "blocky";
      folder = "Blocky";
      type = "file";
      disableDeletion = false;
      editable = false;

      options.path = pkgs.fetchurl {
        url = "https://0xerr0r.github.io/blocky/latest/blocky-grafana.json";
        hash = "sha256-InIKXAmovhDfYqBFGDNk/Cyj0hQQVjTuyDdTumV2yOg=";
      };
    }
  ];
}
