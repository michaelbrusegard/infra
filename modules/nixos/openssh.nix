{
  config,
  lib,
  isWsl,
  ...
}:
{
  services.openssh = {
    enable = true;
    openFirewall = true;
    startWhenNeeded = true;
    inherit (config.secrets.openssh) ports;
    authorizedKeysInHomedir = false;
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
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
// lib.optionalAttrs (!isWsl) {
  environment.persistence."/persistent".directories = [
    "/var/lib/fail2ban"
  ];
}
