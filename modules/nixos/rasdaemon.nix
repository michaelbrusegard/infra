_: {
  hardware.rasdaemon = {
    enable = true;
    record = true;
  };
  environment.persistence."/persistent".directories = ["/var/lib/rasdaemon"];
}
