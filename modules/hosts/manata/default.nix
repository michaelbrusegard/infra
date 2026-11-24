{inputs, ...}: {
  hosts.manata = {
    system = "aarch64-linux";
    users = ["admin" "deploy"];
    platform = "raspberrypi";
    deploy = {};
  };

  flake.modules.nixos.manata = {lib, ...}: {
    imports = [
      inputs.self.modules.nixos.boot
      inputs.self.modules.nixos.console
      inputs.self.modules.nixos.disable-documentation
      inputs.self.modules.nixos.impermanence
      inputs.self.modules.nixos.locale
      inputs.self.modules.nixos.networking
      inputs.self.modules.nixos.nh
      inputs.self.modules.nixos.nix
      inputs.self.modules.nixos.openssh
      inputs.self.modules.nixos.prometheus
      inputs.self.modules.nixos.restic-server
      inputs.self.modules.nixos.sd-grow
      inputs.self.modules.nixos.security
      inputs.self.modules.nixos.watchdog
      inputs.self.modules.nixos.zsh-admin-rc
    ];

    time.timeZone = "Europe/Oslo";

    # Keep both backup targets from running their expensive maintenance at the
    # same time. Freddo retains the module defaults on the weekend.
    systemd.timers = {
      restic-maintenance.timerConfig = {
        OnCalendar = lib.mkForce "*-*-* 16:00";
        RandomizedDelaySec = lib.mkForce "1h";
      };
      restic-prune.timerConfig = {
        OnCalendar = lib.mkForce "Wed 14:00";
        RandomizedDelaySec = lib.mkForce "1h";
      };
      restic-check.timerConfig = {
        OnCalendar = lib.mkForce "Thu 08:00";
        RandomizedDelaySec = lib.mkForce "2h";
      };
    };

    services.restic.server = {
      initializeRepositories = {
        manafishrov-stalwart = ["pvc"];
        n8n = ["pvc"];
        nextcloud = [
          "postgres"
          "pvc"
        ];
        pocket-id = ["pvc"];
        roundcube = ["pvc"];
        vaultwarden = ["pvc"];
      };

      # The client remains disabled until manata is reachable and a restore has
      # been proven. Avoid alerting on the intentionally empty repository.
      maintenance.freshness.excludedRepositories = ["manafishrov-stalwart/pvc"];
    };

    system.stateVersion = "26.05";
  };
}
