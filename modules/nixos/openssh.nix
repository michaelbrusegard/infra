{config, ...}: {
  services.openssh = {
    enable = true;
    openFirewall = true;
    startWhenNeeded = true;
    inherit (config.secrets.openssh) ports;
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
