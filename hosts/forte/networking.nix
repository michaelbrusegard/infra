{
  networking = {
    wireless.iwd.enable = true;
    networkmanager = {
      enable = true;
      wifi = {
        backend = "iwd";
        powersave = false;
      };
    };
    dhcpcd.enable = false;
  };

  environment.persistence."/persistent".directories = [
    "/etc/NetworkManager/system-connections"
    "/var/lib/iwd"
  ];
}
