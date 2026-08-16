{
  inputs,
  lib,
  ...
}: {
  imports = [
    inputs.self.nixosModules.boot
    inputs.self.nixosModules.console
    inputs.self.nixosModules.disable-documentation
    inputs.self.nixosModules.impermanence
    inputs.self.nixosModules.locale
    inputs.self.nixosModules.networking
    inputs.self.nixosModules.nh
    inputs.self.nixosModules.nix
    inputs.self.nixosModules.openssh
    inputs.self.nixosModules.prometheus
    inputs.self.nixosModules.restic-server
    inputs.self.nixosModules.sd-grow
    inputs.self.nixosModules.security
    inputs.self.nixosModules.watchdog
    inputs.self.nixosModules.zsh-admin-rc
    ./hardware.nix
    ./networking.nix
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

  services.restic.server.initializeRepositories = {
    n8n = ["pvc"];
    nextcloud = [
      "postgres"
      "pvc"
    ];
    pocket-id = ["pvc"];
    roundcube = ["pvc"];
    twenty = [
      "postgres"
      "pvc"
      "s3"
    ];
    vaultwarden = ["pvc"];
  };

  system.stateVersion = "26.05";
}
