{
  config,
  inputs,
  lib,
  users,
  ...
}: let
  persistPath = "/persistent";

  baseDirectories = [
    "/etc/ssh"
    "/root"
    "/var/lib/nixos"
    "/var/lib/systemd"
    "/var/log"
  ];

  userDirectories =
    map (user: {
      directory = "/home/${user}";
      inherit user;
      inherit (config.users.users.${user}) group;
      mode = "u=rwx,g=,o=";
    })
    users;

  serviceDirectories =
    lib.optionals config.services.k3s.enable [
      "/var/lib/rancher/k3s"
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
    ++ lib.optionals config.networking.networkmanager.enable [
      "/etc/NetworkManager/system-connections"
    ]
    ++ lib.optionals config.boot.lanzaboote.enable [
      config.boot.lanzaboote.pkiBundle
    ];

  persistedDirectories = lib.unique (baseDirectories ++ userDirectories ++ serviceDirectories);

  persistedFiles = [
    "/etc/machine-id"
  ];
in {
  imports = [
    inputs.impermanence.nixosModules.impermanence
  ];

  environment.persistence.${persistPath} = {
    hideMounts = true;
    directories = persistedDirectories;
    files = persistedFiles;
  };

  sops.age.sshKeyPaths = ["${persistPath}/etc/ssh/ssh_host_ed25519_key"];
}
