{inputs, ...}: {
  imports = [
    inputs.self.nixosModules.avahi
    inputs.self.nixosModules.binfmt
    inputs.self.nixosModules.boot
    inputs.self.nixosModules.catppuccin
    inputs.self.nixosModules.console
    inputs.self.nixosModules.dialpad
    inputs.self.nixosModules.disko
    inputs.self.nixosModules.dms-greeter
    inputs.self.nixosModules.dms-shell
    inputs.self.nixosModules.dsearch
    inputs.self.nixosModules.fonts
    inputs.self.nixosModules.flatpak
    inputs.self.nixosModules.gaming
    inputs.self.nixosModules.gtk
    inputs.self.nixosModules.handy
    inputs.self.nixosModules.home-manager
    inputs.self.nixosModules.hyprland
    inputs.self.nixosModules.impermanence
    inputs.self.nixosModules.kanata
    inputs.self.nixosModules.lanzaboote
    inputs.self.nixosModules.libvirt
    inputs.self.nixosModules.locale
    inputs.self.nixosModules.localsend
    inputs.self.nixosModules.location
    inputs.self.nixosModules.netbird
    inputs.self.nixosModules.networking
    inputs.self.nixosModules.nh
    inputs.self.nixosModules.nix
    inputs.self.nixosModules.openssh
    inputs.self.nixosModules.pipewire
    inputs.self.nixosModules.plymouth
    inputs.self.nixosModules.security
    inputs.self.nixosModules.ssh-agent
    inputs.self.nixosModules.udisks2
    inputs.self.nixosModules.virtualisation
    inputs.self.nixosModules.wooting
    inputs.self.nixosModules.xdg-portal
    ./disko.nix
    ./hardware.nix
    ./networking.nix
  ];

  time.timeZone = "America/Los_Angeles";

  system.stateVersion = "26.05";
}
