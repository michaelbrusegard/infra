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
    # extraComponents inherits the module's default, which keeps onboarding
    # and platform detection working. Integrations added through the UI live
    # in .storage where nix cannot see them, so their components belong here
    # when adding one fails on missing requirements.
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
