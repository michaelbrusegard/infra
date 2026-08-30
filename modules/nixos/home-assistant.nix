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

  # The declared configuration references these, but home assistant only
  # creates them when it owns the skeleton itself. Referencing a missing file
  # fails the whole yaml parse and boots into recovery mode.
  systemd.tmpfiles.rules = [
    "f ${config.services.home-assistant.configDir}/automations.yaml 0600 hass hass -"
    "f ${config.services.home-assistant.configDir}/scripts.yaml 0600 hass hass -"
    "f ${config.services.home-assistant.configDir}/scenes.yaml 0600 hass hass -"
  ];

  environment.persistence."/persistent".directories = [
    {
      directory = config.services.home-assistant.configDir;
      user = "hass";
      group = "hass";
      mode = "0700";
    }
  ];
}
