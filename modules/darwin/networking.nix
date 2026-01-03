{name, ...}: {
  networking = {
    applicationFirewall = {
      enable = true;
      allowSigned = true;
      allowSignedApp = true;
    };
    hostName = name;
    computerName = name;
  };
}
