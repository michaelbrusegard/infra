{inputs, ...}: {
  hosts.lungo = {
    system = "aarch64-darwin";
    users = ["michaelbrusegard"];
  };

  flake.modules.darwin.lungo = {
    imports = [
      inputs.self.modules.darwin.aerospace
      inputs.self.modules.darwin.fonts
      inputs.self.modules.darwin.home-manager
      inputs.self.modules.darwin.homebrew
      inputs.self.modules.darwin.jankyborders
      inputs.self.modules.darwin.kanata
      inputs.self.modules.darwin.localsend
      inputs.self.modules.darwin.networking
      inputs.self.modules.darwin.nh
      inputs.self.modules.darwin.nix
      inputs.self.modules.darwin.openssh
      inputs.self.modules.darwin.security
      inputs.self.modules.darwin.system
      inputs.self.modules.darwin.tailscale
      inputs.self.modules.darwin.virtualisation
      inputs.self.modules.darwin.wallpaper
    ];

    time.timeZone = "America/Los_Angeles";

    system.stateVersion = 5;
  };
}
