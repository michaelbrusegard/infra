{
  networking = {
    wireless.iwd.enable = true;
    networkmanager = {
      enable = true;
      wifi.backend = "iwd";
      connectionConfig."ethernet.wake-on-lan" = 64;
    };
    dhcpcd.enable = false;
  };

  environment.persistence."/persistent".directories = [
    "/etc/NetworkManager/system-connections"
    "/var/lib/iwd"
  ];
}
