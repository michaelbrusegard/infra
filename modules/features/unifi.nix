{
  flake.modules.nixos.unifi = {
    services.unifi.enable = true;

    environment.persistence."/persistent".directories = [
      "/var/lib/unifi"
    ];
  };
}
