{
  nixpkgs-otbr,
  ...
}: {
  imports = [
    "${nixpkgs-otbr}/nixos/modules/services/home-automation/openthread-border-router.nix"
  ];
  services.matter-server.enable = true;
  services.openthread-border-router = {
    enable = true;
    backboneInterface = "end0";
    rest.listenAddress = "0.0.0.0";
    web.listenAddress = "0.0.0.0";
  };
}
