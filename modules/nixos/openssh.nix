{config, ...}: {
  services.openssh = {
    enable = true;
    openFirewall = true;
    startWhenNeeded = true;
    ports = config.secrets.openssh.ports;
    authorizedKeys.keys = config.secrets.openssh.authorizedKeys.keys;
    authorizedKeysInHomedir = false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
  services.fail2ban = {
    enable = true;
    bantime = "1h";
  };
}
