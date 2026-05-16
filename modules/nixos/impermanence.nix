{
  config,
  inputs,
  lib,
  users,
  ...
}: let
  persistPath = "/persistent";

  baseDirectories = [
    "/root"
    "/var/lib/nixos"
    "/var/lib/systemd"
    "/var/log"
  ];

  userPersistence = {
    admin.files = [
      ".config/sops/age/keys.txt"
      ".config/zsh/.zsh_history"
    ];
    michaelbrusegard = {
      directories = [
        "Desktop"
        "Documents"
        "Downloads"
        "Music"
        "Pictures"
        "Projects"
        "Public"
        "Templates"
        "Videos"
      ];
      files = [
        ".config/sops/age/keys.txt"
        ".config/zsh/.zsh_history"
      ];
    };
  };

  serviceDirectories =
    lib.optionals config.services.k3s.enable [
      "/var/lib/rancher/k3s"
      "/var/local/openebs"
    ]
    ++ lib.optionals config.services.fail2ban.enable [
      "/var/lib/fail2ban"
    ]
    ++ lib.optionals config.services.mosquitto.enable [
      config.services.mosquitto.dataDir
    ]
    ++ lib.optionals config.services.homebridge.enable [
      config.services.homebridge.userStoragePath
    ]
    ++ lib.optionals config.services.zigbee2mqtt.enable [
      config.services.zigbee2mqtt.dataDir
    ]
    ++ lib.optionals config.services.prometheus.enable [
      "/var/lib/${config.services.prometheus.stateDir}"
    ]
    ++ lib.optionals config.services.unifi.enable [
      "/var/lib/unifi"
    ]
    ++ lib.optionals (config.services.netbird.clients != {}) [
      config.services.netbird.clients.default.dir.state
    ]
    ++ lib.optionals config.networking.networkmanager.enable [
      "/etc/NetworkManager/system-connections"
    ]
    ++ lib.optionals (config.boot.lanzaboote.enable or false) [
      config.boot.lanzaboote.pkiBundle
    ];

  persistedDirectories = lib.unique (baseDirectories ++ serviceDirectories);

  persistedFiles = [
    "/etc/machine-id"
    "/etc/ssh/ssh_host_ed25519_key"
    "/etc/ssh/ssh_host_ed25519_key.pub"
  ];
in {
  imports = [
    inputs.impermanence.nixosModules.impermanence
  ];

  environment.persistence.${persistPath} = {
    hideMounts = true;
    directories = persistedDirectories;
    files = persistedFiles;
    users = lib.filterAttrs (user: _: builtins.elem user users) userPersistence;
  };

  systemd.tmpfiles.rules = [
    "z /etc/ssh/ssh_host_ed25519_key 0600 root root -"
    "z /etc/ssh/ssh_host_ed25519_key.pub 0644 root root -"
  ];

  sops.age.sshKeyPaths = ["${persistPath}/etc/ssh/ssh_host_ed25519_key"];
}
