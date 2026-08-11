{
  inputs,
  pkgs,
  ...
}: let
  mkNetconsoleCollector = node: port: {
    wantedBy = ["multi-user.target"];
    after = ["network.target"];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat -u UDP-RECVFROM:${toString port},fork,reuseaddr OPEN:/var/log/netconsole/${node}.log,creat,append";
      Restart = "on-failure";
      RestartSec = 5;
      DynamicUser = false;
      LogsDirectory = "netconsole";
    };
  };
in {
  imports = [
    inputs.self.nixosModules.alloy
    inputs.self.nixosModules.boot
    inputs.self.nixosModules.blocky
    inputs.self.nixosModules.catppuccin
    inputs.self.nixosModules.console
    inputs.self.nixosModules.cloudflare-dyndns
    inputs.self.nixosModules.disable-documentation
    inputs.self.nixosModules.disko
    inputs.self.nixosModules.homebridge
    inputs.self.nixosModules.home-manager
    inputs.self.nixosModules.impermanence
    inputs.self.nixosModules.lanzaboote
    inputs.self.nixosModules.locale
    inputs.self.nixosModules.networking
    inputs.self.nixosModules.nh
    inputs.self.nixosModules.nix
    inputs.self.nixosModules.openssh
    inputs.self.nixosModules.security
    inputs.self.nixosModules.unifi
    inputs.self.nixosModules.wake-on-lan
    inputs.self.nixosModules.watchdog
    ./disko.nix
    ./hardware.nix
    ./networking.nix
  ];

  time.timeZone = "Europe/Oslo";

  system.stateVersion = "25.11";

  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = ["systemd"];
  };

  # Separate files retain sender identity because base netconsole payloads do
  # not include a hostname or source address.
  systemd.services = {
    netconsole-collector-espresso-0 = mkNetconsoleCollector "espresso-0" 6666;
    netconsole-collector-espresso-1 = mkNetconsoleCollector "espresso-1" 6667;
    netconsole-collector-espresso-2 = mkNetconsoleCollector "espresso-2" 6668;
  };

  # Bound the logs; a crash-looping node could otherwise grow them unbounded
  # since they are plain files, not journald-managed.
  services.logrotate.settings."/var/log/netconsole/*.log" = {
    frequency = "weekly";
    rotate = 4;
    compress = true;
    missingok = true;
    notifempty = true;
  };

  environment.etc."alloy/config.alloy".text = ''
    loki.source.journal "macchiato" {
      forward_to = [loki.process.journal.receiver]
      labels = {
        host = "macchiato",
        job  = "systemd-journal",
      }
    }

    loki.source.file "netconsole" {
      targets    = [{ __path__ = "/var/log/netconsole/*.log" }]
      forward_to = [loki.write.default.receiver]
    }

    loki.process "journal" {
      forward_to = [loki.write.default.receiver]
    }

    loki.write "default" {
      endpoint {
        url = "http://10.0.188.4:3100/loki/api/v1/push"
      }
    }
  '';
}
