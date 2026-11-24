{ inputs, ... }: {
  hosts.cortado = {
    system = "x86_64-linux";
    users = [
      "admin"
      "deploy"
    ];
    deploy.buildOnTarget = true;
  };

  flake.modules.nixos.cortado = {
    imports = with inputs.self.modules.nixos; [
      router
      home-assistant
      netbird-relay
      smtp-backup
    ];

    time.timeZone = "America/Los_Angeles";

    system.stateVersion = "26.05";

    services.prometheus.exporters.node = {
      enable = true;
      enabledCollectors = [ "systemd" ];
    };

    # Host deltas on the module's skeleton: caddy terminates TLS on this box, so
    # home assistant must trust the loopback proxy, and links it generates
    # should use the published name.
    services.home-assistant.config = {
      homeassistant.external_url = "https://home-assistant.midgard.michaelbrusegard.com";
      http = {
        use_x_forwarded_for = true;
        trusted_proxies = [
          "127.0.0.1"
          "::1"
        ];
      };
    };
  };
}
