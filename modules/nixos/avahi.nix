{
  lib,
  isWsl,
  ...
}: {
  services.avahi = lib.mkIf (!isWsl) {
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
