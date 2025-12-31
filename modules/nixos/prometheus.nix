_: {
  services.prometheus = {
    enable = true;

    globalConfig = {
      scrape_interval = "15s";
      evaluation_interval = "15s";
    };
  };
}
