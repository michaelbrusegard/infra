{
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

  # App-owned user state is colocated in the owning home-manager modules
  # (via the homePersistenceRoot guard). Only identity material and the
  # generic XDG user directories stay centralized here.
  userPersistence = {
    admin.files = [
      ".config/sops/age/keys.txt"
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
      ];
    };
  };

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
    directories = baseDirectories;
    files = persistedFiles;
    users = lib.filterAttrs (user: _: builtins.elem user users) userPersistence;
  };

  systemd.tmpfiles.rules = [
    "d /etc/ssh 0755 root root -"
    "z /etc/ssh/ssh_host_ed25519_key 0600 root root -"
    "z /etc/ssh/ssh_host_ed25519_key.pub 0644 root root -"
  ];

  sops.age.sshKeyPaths = ["${persistPath}/etc/ssh/ssh_host_ed25519_key"];
}
