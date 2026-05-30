{config, ...}: {
  services.prometheus = {
    enable = true;

    globalConfig = {
      scrape_interval = "15s";
      evaluation_interval = "15s";
    };
  };

  environment.persistence."/persistent".directories = [
    "/var/lib/${config.services.prometheus.stateDir}"
  ];
}
