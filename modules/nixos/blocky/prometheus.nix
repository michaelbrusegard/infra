{...}: {
  services.blocky.settings.prometheus.enable = true;

  services.prometheus.scrapeConfigs = [
    {
      job_name = "blocky";
      static_configs = [
        {targets = ["127.0.0.1:4000"];}
      ];
    }
  ];
}
