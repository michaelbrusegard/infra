{inputs, ...}: {
  flake.modules.nixos.router.imports = with inputs.self.modules.nixos; [
    server
    blocky
    cloudflare-dyndns
    disko
    lanzaboote
    netbird
    unifi
  ];
}
