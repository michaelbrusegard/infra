{inputs, ...}: {
  hosts.forte = {
    system = "x86_64-linux";
    users = ["michaelbrusegard"];
  };

  flake.modules.nixos.forte = {
    imports = [
      inputs.self.modules.nixos.avahi
      inputs.self.modules.nixos.binfmt
      inputs.self.modules.nixos.boot
      inputs.self.modules.nixos.catppuccin
      inputs.self.modules.nixos.console
      inputs.self.modules.nixos.dialpad
      inputs.self.modules.nixos.disko
      inputs.self.modules.nixos.dms-greeter
      inputs.self.modules.nixos.dms-shell
      inputs.self.modules.nixos.fonts
      inputs.self.modules.nixos.flatpak
      inputs.self.modules.nixos.gaming
      inputs.self.modules.nixos.gtk
      inputs.self.modules.nixos.home-manager
      inputs.self.modules.nixos.hyprland
      inputs.self.modules.nixos.impermanence
      inputs.self.modules.nixos.kanata
      inputs.self.modules.nixos.lanzaboote
      inputs.self.modules.nixos.libvirt
      inputs.self.modules.nixos.locale
      inputs.self.modules.nixos.localsend
      inputs.self.modules.nixos.location
      inputs.self.modules.nixos.netbird
      inputs.self.modules.nixos.networking
      inputs.self.modules.nixos.nh
      inputs.self.modules.nixos.nix
      inputs.self.modules.nixos.openssh
      inputs.self.modules.nixos.pipewire
      inputs.self.modules.nixos.plymouth
      inputs.self.modules.nixos.rustdesk
      inputs.self.modules.nixos.security
      inputs.self.modules.nixos.ssh-agent
      inputs.self.modules.nixos.tailscale
      inputs.self.modules.nixos.udisks2
      inputs.self.modules.nixos.virtualisation
      inputs.self.modules.nixos.wooting
      inputs.self.modules.nixos.xdg-portal
    ];

    time.timeZone = "America/Los_Angeles";

    system.stateVersion = "26.05";
  };
}
