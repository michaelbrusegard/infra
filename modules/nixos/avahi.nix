{ ... }:

{
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    nssmdns6 = true;
    reflector = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };
}
