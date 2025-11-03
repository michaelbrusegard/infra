{ config, ... }: {
  services = {
    kanata = {
      enable = true;
      keyboards.default.configFile = ../../assets/keyboard/kanata-linux.kbd;
    };
    openssh = {
      enable = true;
      openFirewall = true;
      startWhenNeeded = true;
      ports = config.secrets.desktop.ssh.ports;
      authorizedKeysInHomedir = false;
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
      allowInterfaces = [ "enp6s0" ];
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
    };
    pipewire = {
      enable = true;
      jack.enable = true;
      pulse.enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
    };
    greetd.enable = true;
    udisks2.enable = true;
  };
}
