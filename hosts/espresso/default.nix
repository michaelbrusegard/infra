{inputs, ...}: {
  imports = [
    inputs.self.nixosModules.boot
    inputs.self.nixosModules.catppuccin
    inputs.self.nixosModules.console
    inputs.self.nixosModules.disable-documentation
    inputs.self.nixosModules.disko
    inputs.self.nixosModules.home-manager
    inputs.self.nixosModules.lanzaboote
    inputs.self.nixosModules.locale
    inputs.self.nixosModules.networking
    inputs.self.nixosModules.nix
    inputs.self.nixosModules.security
    ./k3s.nix
    ./networking.nix
    ./hardware.nix
    ./disko.nix
  ];

  system.stateVersion = "25.11";

  systemd.tmpfiles.rules = [
    "d /var/lib/longhorn 0755 root root - -"
    "h /var/lib/longhorn - - - - +C"
    "d /var/lib/rancher/k3s 0755 root root - -"
    "h /var/lib/rancher/k3s - - - - +C"
  ];
}
