{config, ...}: {
  services.home-assistant = {
    enable = true;
    # The yaml skeleton onboarding would generate, owned declaratively. The
    # include files stay real writable files, so the UI keeps its automation
    # editors, and integrations, devices, and dashboards stay in .storage.
    # Hosts merge in their own deltas such as proxy trust and external urls.
    config = {
      default_config = {};
      frontend.themes = "!include_dir_merge_named themes";
      automation = "!include automations.yaml";
      script = "!include scripts.yaml";
      scene = "!include scenes.yaml";
    };
    extraComponents = [
      "backup"
      "bluetooth"
      "config"
      "dhcp"
      "energy"
      "go2rtc"
      "history"
      "homeassistant_alerts"
      "image_upload"
      "logbook"
      "media_source"
      "mobile_app"
      "my"
      "ssdp"
      "stream"
      "sun"
      "usb"
      "webhook"
      "zeroconf"
      "zha"
      "met"
      "otbr"
      "thread"
      "matter"
    ];
  };

  environment.persistence."/persistent".directories = [
    {
      directory = config.services.home-assistant.configDir;
      user = "hass";
      group = "hass";
      mode = "0700";
    }
  ];
}
