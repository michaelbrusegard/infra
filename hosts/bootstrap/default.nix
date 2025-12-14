{ lib, modulesPath, dotfiles-private, ... }: {
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };
  users.users.root.openssh.authorizedKeys.keys = dotfiles-private.bootstrap.ssh.authorizedKeys;
  networking = {
    useDHCP = lib.mkForce true;
    networkmanager.enable = lib.mkForce false;
  };
  services.udisks2.enable = false;
  systemd.services.sshd.wantedBy = [ "multi-user.target" ];
  system.stateVersion = "25.11";
}
