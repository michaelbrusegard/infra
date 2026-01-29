{
  inputs,
  ...
}: {
  imports = [
    inputs.self.nixosModules.boot
    inputs.self.nixosModules.bluetooth
    inputs.self.nixosModules.catppuccin
    inputs.self.nixosModules.console
    inputs.self.nixosModules.disko
    inputs.self.nixosModules.dms-greeter
    inputs.self.nixosModules.dms-shell
    inputs.self.nixosModules.fonts
    inputs.self.nixosModules.gtk
    inputs.self.nixosModules.home-manager
    inputs.self.nixosModules.hyprland
    inputs.self.nixosModules.kanata
    inputs.self.nixosModules.lanzaboote
    inputs.self.nixosModules.libvirt
    inputs.self.nixosModules.locale
    inputs.self.nixosModules.location
    inputs.self.nixosModules.networking
    inputs.self.nixosModules.nix
    inputs.self.nixosModules.openssh
    inputs.self.nixosModules.pipewire
    inputs.self.nixosModules.plymouth
    inputs.self.nixosModules.security
    inputs.self.nixosModules.ssh-agent
    inputs.self.nixosModules.udisks2
    inputs.self.nixosModules.virtualisation
    inputs.self.nixosModules.xdg-portal
    ./disko.nix
    ./hardware.nix
    ./networking.nix
  ];

  system.stateVersion = "25.11";

  services.displayManager.dms-greeter.configHome = "/home/michaelbrusegard";
}
