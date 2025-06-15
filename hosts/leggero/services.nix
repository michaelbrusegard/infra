{ config, ... }: {
  services = {
    openssh = {
      enable = true;
      openFirewall = true;
      startWhenNeeded = true;
      ports = config.secrets.leggeroSshPorts;
      authorizedKeysInHomedir = false;
      authorizedKeysFiles = config.secrets.leggeroAuthorizedKeysFiles;
      hostKeys = [];
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };
    fail2ban = {
      enable = true;
      bantime = "1h";
    };
    avahi = {
      enable = true;
      nssmdns4 = true;
      nssmdns6 = true;
      allowInterfaces = [ "eth0" ];
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
    };
  };
}
