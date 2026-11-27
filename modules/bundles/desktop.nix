{ inputs, ... }: {
  flake.modules.nixos.desktop.home-manager.sharedModules = [
    inputs.self.modules.homeManager.desktop
  ];

  flake.modules.nixos.desktop.imports = with inputs.self.modules.nixos; [
    workstation
    avahi
    binfmt
    console
    disko
    dms-greeter
    dms-shell
    fonts
    gaming
    gtk
    helium
    hyprland
    impermanence
    kanata
    lanzaboote
    localsend
    location
    netbird
    pipewire
    plymouth
    rustdesk
    tailscale
    udisks2
    wooting
    xdg-portal
  ];
}
