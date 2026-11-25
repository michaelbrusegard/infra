{ inputs, ... }: {
  hosts.manata = {
    system = "aarch64-linux";
    users = [
      "admin"
      "deploy"
    ];
    platform = "raspberrypi";
    deploy = { };
  };

  flake.modules.nixos.manata = { lib, ... }: {
    imports = with inputs.self.modules.nixos; [
      backup-server
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
        manafishrov-stalwart = [ "pvc" ];
        n8n = [ "pvc" ];
        nextcloud = [
          "postgres"
          "pvc"
        ];
        pocket-id = [ "pvc" ];
        roundcube = [ "pvc" ];
        vaultwarden = [ "pvc" ];
      };

      # The client remains disabled until manata is reachable and a restore has
      # been proven. Avoid alerting on the intentionally empty repository.
      maintenance.freshness.excludedRepositories = [ "manafishrov-stalwart/pvc" ];
    };

    system.stateVersion = "26.05";
  };
}
