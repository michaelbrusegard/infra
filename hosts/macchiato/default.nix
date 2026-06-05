{
  inputs,
  pkgs,
  ...
}: {
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
    inputs.self.nixosModules.watchdog
    ./disko.nix
    ./hardware.nix
    ./networking.nix
  ];

  system.stateVersion = "25.11";

  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = ["systemd"];
  };

  # Receive netconsole UDP from the espresso nodes and tail it into Loki.
  systemd.services.netconsole-collector = {
    wantedBy = ["multi-user.target"];
    after = ["network.target"];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat -u UDP-RECVFROM:6666,fork,reuseaddr OPEN:/var/log/netconsole.log,creat,append";
      Restart = "on-failure";
      RestartSec = 5;
      DynamicUser = false;
    };
  };

  # Bound the netconsole log; a crash-looping node could otherwise grow it
  # unbounded since it is a plain file, not journald-managed.
  services.logrotate.settings."/var/log/netconsole.log" = {
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
      targets    = [{ __path__ = "/var/log/netconsole.log" }]
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
