{inputs, ...}: {
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

  services.restic.server.initializeRepositories = {
    bazarr = ["repo-config"];
    hermes-agent = ["pvc"];
    honcho = ["postgres"];
    immich = [
      "postgres"
      "uploads"
    ];
    jellyfin = ["repo-config"];
    minecraft-creative = ["world"];
    minecraft-revelation = ["world"];
    minecraft-vanilla = ["world"];
    media-music = ["repo-library"];
    musicgrabber = ["repo-config"];
    navidrome = ["repo-data"];
    netbird = ["pvc"];
    nextcloud = [
      "postgres"
      "pvc"
    ];
    pocket-id = ["pvc"];
    prowlarr = ["repo-config"];
    radarr = ["repo-config"];
    seerr = ["repo-config"];
    sonarr = ["repo-config"];
    stalwart = ["pvc"];
    transmission = ["repo-config"];
  };

  services.restic.server.maintenance.keepTags = ["legacy-minecraft"];

  system.stateVersion = "26.05";
}
