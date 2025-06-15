{ config, ... }: {
  services = {
    openssh = {
      enable = true;
      openFirewall = true;
      startWhenNeeded = true;
      ports = config.secrets.leggero.sshPorts;
      authorizedKeysInHomedir = false;
      authorizedKeysFiles = config.secrets.leggero.authorizedKeysFiles;
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
    cloudflare-dyndns = {
      enable = true;
      apiTokenFile = config.secrets.credentialFiles.cloudflareToken;
      domains = config.secrets.leggero.ddnsDomains;
      ipv4 = true;
      ipv6 = true;
    };
  };
}
