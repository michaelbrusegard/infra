_: {
  nixpkgs.config.permittedInsecurePackages = [
    "unifi-controller-9.5.21"
  ];
  services.unifi.enable = true;
}
