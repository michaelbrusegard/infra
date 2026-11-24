{ inputs, ... }: {
  flake.modules.nixos.workstation.imports = with inputs.self.modules.nixos; [
    base
    catppuccin
    home-manager
    ssh-agent
    virtualisation
  ];
}
