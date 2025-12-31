{config, ...}: {
  services = {
    homebridge = {
      enable = true;
      openFirewall = true;
      settings = {
        bridge = {
          inherit (config.secrets.homebridge.settings.bridge) username;
          inherit (config.secrets.homebridge.settings.bridge) pin;
          port = 51826;
        };
        platforms = [
          {
            name = "zigbee2mqtt";
            platform = "zigbee2mqtt";
            mqtt = {
              server = "mqtt://127.0.0.1:1883";
              base_topic = "zigbee2mqtt";
              version = 5;
            };
          }
        ];
      };
    };

    zigbee2mqtt = {
      enable = true;
      settings = {
        mqtt.server = "mqtt://127.0.0.1:1883";
        frontend.enabled = true;
        availability.enabled = true;
      };
    };

    mosquitto = {
      enable = true;
      listeners = [
        {
          address = "127.0.0.1";
          acl = ["pattern readwrite #"];
          omitPasswordAuth = true;
          settings.allow_anonymous = true;
        }
      ];
    };
  };

  users.users.zigbee2mqtt.extraGroups = ["dialout"];
}
