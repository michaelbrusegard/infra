{ config, modulesPath, dotfiles-private, ... }: {
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    dotfiles-private.nixosModules.secrets
  ];
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };
  users.users.root.openssh.authorizedKeys.keys = config.secrets.bootstrap.ssh.authorizedKeys;
  networking.useDHCP = true;
  services.udisks2.enable = false;
  systemd.services.sshd.wantedBy = [ "multi-user.target" ];
  system.stateVersion = "25.11";
}
