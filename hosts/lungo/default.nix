{inputs, ...}: {
  imports = [
    inputs.self.darwinModules.aerospace
    inputs.self.darwinModules.fonts
    inputs.self.darwinModules.home-manager
    inputs.self.darwinModules.homebrew
    inputs.self.darwinModules.jankyborders
    inputs.self.darwinModules.kanata
    inputs.self.darwinModules.localsend
    inputs.self.darwinModules.networking
    inputs.self.darwinModules.nh
    inputs.self.darwinModules.nix
    inputs.self.darwinModules.openssh
    inputs.self.darwinModules.security
    inputs.self.darwinModules.system
    inputs.self.darwinModules.virtualisation
    inputs.self.darwinModules.wallpaper
  ];

  time.timeZone = "America/Los_Angeles";

  system.stateVersion = 5;
}
