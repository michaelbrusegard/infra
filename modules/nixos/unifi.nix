_: {
  services.unifi.enable = true;

  environment.persistence."/persistent".directories = [
    "/var/lib/unifi"
  ];
}
