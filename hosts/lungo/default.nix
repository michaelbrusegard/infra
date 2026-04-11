{inputs, ...}: {
  imports = [
    inputs.self.darwinModules.fonts
    inputs.self.darwinModules.home-manager
    inputs.self.darwinModules.homebrew
    inputs.self.darwinModules.kanata
    inputs.self.darwinModules.netbird
    inputs.self.darwinModules.networking
    inputs.self.darwinModules.nix
    inputs.self.darwinModules.openssh
    inputs.self.darwinModules.security
    inputs.self.darwinModules.system
    inputs.self.darwinModules.virtualisation
    inputs.self.darwinModules.yabai
  ];

  system.stateVersion = 5;
}
