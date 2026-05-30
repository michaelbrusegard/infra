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

  userPersistence = {
    admin.files = [
      ".config/sops/age/keys.txt"
      ".config/zsh/.zsh_history"
    ];
    michaelbrusegard = {
      directories = [
        ".cache/antidote"
        ".cache/direnv"
        ".config/opencode"
        ".local/share/direnv"
        ".local/share/opencode"
        ".local/share/zoxide"
        ".local/state/pnpm"
        ".omo"
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
        ".ssh/known_hosts"
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
    "z /etc/ssh/ssh_host_ed25519_key 0600 root root -"
    "z /etc/ssh/ssh_host_ed25519_key.pub 0644 root root -"
  ];

  sops.age.sshKeyPaths = ["${persistPath}/etc/ssh/ssh_host_ed25519_key"];
}
