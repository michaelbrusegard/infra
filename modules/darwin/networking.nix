{hostname, ...}: {
  networking = {
    applicationFirewall = {
      enable = true;
      allowSigned = true;
      allowSignedApp = true;
    };
    hostName = hostname;
    computerName = hostname;
  };
}
