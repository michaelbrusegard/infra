{
  networking = {
    wireless.iwd.enable = true;
    networkmanager = {
      enable = true;
      wifi.backend = "iwd";
    };
    dhcpcd.enable = false;
    interfaces.enp6s0.wakeOnLan.enable = true;
  };

  environment.persistence."/persistent".directories = [
    "/etc/NetworkManager/system-connections"
    "/var/lib/iwd"
  ];
}
